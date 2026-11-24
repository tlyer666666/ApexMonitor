#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[2]

def bundle(path, identifier="com.macpulse.monitor"):
    (path / "Contents/MacOS").mkdir(parents=True)
    with (path / "Contents/Info.plist").open("wb") as file:
        plistlib.dump({"CFBundleIdentifier": identifier, "CFBundleExecutable": "MacPulse"}, file)
    executable = path / "Contents/MacOS/MacPulse"
    executable.write_text("#!/bin/sh\nexit 0\n")
    executable.chmod(0o755)

with tempfile.TemporaryDirectory(prefix="macpulse-install-test-") as directory:
    temporary = Path(directory)
    project = temporary / "project"
    (project / "Scripts").mkdir(parents=True)
    shutil.copy2(root / "Scripts/install.sh", project / "Scripts/install.sh")
    stub = project / "Scripts/package-app.sh"
    stub.write_text("#!/bin/sh\nexit 0\n")
    stub.chmod(0o755)
    bundle(project / "dist/MacPulse.app")

    def run(home):
        home.mkdir(parents=True, exist_ok=True)
        env = os.environ | {"HOME": str(home)}
        return subprocess.run(["bash", str(project / "Scripts/install.sh")], env=env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

    home = temporary / "occupied-desktop"
    (home / "Desktop").mkdir(parents=True)
    marker = home / "Desktop/MacPulse"
    marker.write_text("user document: must survive")
    result = run(home)
    assert result.returncode != 0, "installer must refuse a Desktop regular file"
    assert marker.is_file() and not marker.is_symlink() and marker.read_text() == "user document: must survive"
    print("PASS: existing Desktop document is not replaced")

    home = temporary / "foreign-app"
    bundle(home / "Applications/MacPulse.app", "example.other-app")
    result = run(home)
    assert result.returncode != 0, "installer must not overwrite an unrelated app"
    assert plistlib.loads((home / "Applications/MacPulse.app/Contents/Info.plist").read_bytes())["CFBundleIdentifier"] == "example.other-app"
    print("PASS: unrelated app at install destination is preserved")

    home = temporary / "clean-home"
    for _ in range(2):
        result = run(home)
        assert result.returncode == 0, result.stdout
        assert (home / "Desktop/MacPulse").is_symlink()
        assert (home / "Desktop/MacPulse").resolve() == (home / "Applications/MacPulse.app").resolve()
        assert os.access(home / "Applications/MacPulse.app/Contents/MacOS/MacPulse", os.X_OK)
    print("PASS: fresh installation and repeat update preserve the shortcut")

    home = temporary / "failed-link-restores-previous"
    (home / "Desktop").mkdir(parents=True)
    previous = home / "Applications/MacPulse.app"
    bundle(previous)
    (previous / "previous-marker").write_text("previous install")
    (project / "dist/MacPulse.app/next-marker").write_text("new build")
    desktop = home / "Desktop"
    desktop.chmod(0o555)
    try:
        result = run(home)
    finally:
        desktop.chmod(0o755)
    assert result.returncode != 0, "the installer must fail when the shortcut cannot be created"
    assert (previous / "previous-marker").is_file(), "a failed install must restore the previous version"
    assert not (previous / "next-marker").exists(), "the failed build must not remain at the destination"
    assert not list((home / "Applications").glob(".macpulse-install.*")), "cleanup must remove the staging directory"
    assert not (home / "Desktop/MacPulse").is_symlink()
    print("PASS: a failed desktop-link step restores the previous install")

    # Simulate a failed swap: a fake `mv` refuses the staging→destination move
    # (and only that one; the backup move and the cleanup restore still work).
    home = temporary / "failed-swap-restores-previous"
    (home / "Desktop").mkdir(parents=True)
    previous = home / "Applications/MacPulse.app"
    bundle(previous)
    (previous / "previous-marker").write_text("previous install")
    (project / "dist/MacPulse.app/next-marker").write_text("new build")
    bin_dir = temporary / "fake-bin"
    bin_dir.mkdir()
    (bin_dir / "mv").write_text(
        "#!/bin/sh\n"
        'case "$1" in\n'
        "*/.macpulse-install.*/MacPulse.app) echo 'mv: simulated failure' >&2; exit 1;;\n"
        "*) exec /bin/mv \"$@\";;\n"
        "esac\n"
    )
    (bin_dir / "mv").chmod(0o755)
    result = subprocess.run(["bash", str(project / "Scripts/install.sh")],
                            env=os.environ | {"HOME": str(home), "PATH": f"{bin_dir}:/usr/bin:/bin"},
                            capture_output=True, text=True)
    assert result.returncode != 0, "a failed swap must abort, not report success"
    assert (previous / "previous-marker").is_file(), "a failed swap must restore the previous version"
    assert not (previous / "next-marker").exists(), "the failed build must not remain at the destination"
    assert not list((home / "Applications").glob(".macpulse-install.*")), "cleanup must remove the staging directory"
    assert "Installed" not in result.stdout, "a failed swap must not print success"
    print("PASS: a failed swap aborts and restores the previous install")

    # Simulate a TOCTOU swap during package-app.sh: an unrelated app appears at
    # the destination while packaging is running; install.sh must re-verify and refuse.
    home = temporary / "toctou-foreign-app"
    (home / "Applications").mkdir(parents=True)
    toctou_project = temporary / "toctou-project"
    (toctou_project / "Scripts").mkdir(parents=True)
    shutil.copy2(root / "Scripts/install.sh", toctou_project / "Scripts/install.sh")
    bundle(toctou_project / "dist/MacPulse.app")
    toctou_stub = toctou_project / "Scripts/package-app.sh"
    toctou_stub.write_text(
        "#!/bin/sh\n"
        'mkdir -p "$HOME/Applications/MacPulse.app/Contents/MacOS"\n'
        'cat > "$HOME/Applications/MacPulse.app/Contents/Info.plist" <<EOF\n'
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
        '<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>example.other-app</string></dict></plist>\n'
        'EOF\n'
        "exit 0\n"
    )
    toctou_stub.chmod(0o755)
    result = subprocess.run(["bash", str(toctou_project / "Scripts/install.sh")],
                            env=os.environ | {"HOME": str(home)},
                            capture_output=True, text=True)
    assert result.returncode != 0, "installer must re-verify destination after package-app.sh"
    assert plistlib.loads((home / "Applications/MacPulse.app/Contents/Info.plist").read_bytes())["CFBundleIdentifier"] == "example.other-app"
    print("PASS: destination re-verification after packaging preserves an unrelated app")
