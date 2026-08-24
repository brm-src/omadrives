#!/usr/bin/env python3
"""OmaDrives helper: enumerate and manage block devices through udisks2.

Every subcommand prints one JSON object on stdout. The QML layer owns all
user-facing strings that need translation; this helper returns neutral,
already-localized messages via _t().
"""

import argparse
import json
import os
import shutil
import subprocess
import sys

LANG = "en"


def _t(es, en):
    return es if LANG == "es" else en


def run(cmd, timeout=30):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, check=False)


def ok(message="", **extra):
    payload = {"ok": True, "message": message}
    payload.update(extra)
    print(json.dumps(payload))
    sys.exit(0)


def fail(error, **extra):
    payload = {"ok": False, "error": error}
    payload.update(extra)
    print(json.dumps(payload))
    sys.exit(0)


def human_size(num_bytes):
    value = float(num_bytes)
    for unit in ("B", "K", "M", "G", "T"):
        if value < 1024 or unit == "T":
            return ("%.1f%s" % (value, unit)).replace(".0", "")
        value /= 1024.0
    return str(num_bytes)


def load_lsblk():
    result = run(["lsblk", "-J", "-b", "-o",
                  "NAME,PATH,SIZE,FSTYPE,LABEL,MOUNTPOINTS,MOUNTPOINT,RM,RO,TYPE,MODEL,VENDOR"])
    if result.returncode != 0:
        raise RuntimeError(result.stderr.strip() or "lsblk failed")
    return json.loads(result.stdout or "{}")


def load_mount_fstypes():
    result = run(["findmnt", "-rn", "-o", "SOURCE,FSTYPE,TARGET"], timeout=10)
    mounts = {}
    for line in result.stdout.splitlines():
        fields = line.split(None, 2)
        if len(fields) == 3:
            source, fstype, target = fields
            mounts[target] = (source.split("[", 1)[0], fstype.lower())
    return mounts


def iter_partitions(node):
    """Yield leaf partitions/filesystems (skip containers, swaps, roms)."""
    children = node.get("children") or []
    fstype = (node.get("fstype") or "").lower()
    mounts = [m for m in (node.get("mountpoints") or []) if m]
    if fstype == "swap":
        return
    if not children and (fstype or mounts):
        yield node
        return
    if not children:
        return
    for child in children:
        yield from iter_partitions(child)


def drive_kind(node):
    if node.get("rm"):
        return "usb"
    return "internal"


def collect_drives():
    data = load_lsblk()
    mount_fstypes = load_mount_fstypes()
    drives = []
    for device in data.get("blockdevices", []):
        # Skip virtual block devices: zram, loops, md raids.
        name = device.get("name") or ""
        if name.startswith(("zram", "loop", "md", "ram")):
            continue
        parent_model = device.get("model") or ""
        parent_vendor = device.get("vendor") or ""
        parent_rm = bool(device.get("rm"))
        parent_path = device.get("path") or ""
        for part in iter_partitions(device):
            mounts = part.get("mountpoints") or []
            mountpoint = next((m for m in mounts if m), part.get("mountpoint")) or ""
            fstype = (part.get("fstype") or "").lower()
            if not fstype:
                source_fs = mount_fstypes.get(mountpoint)
                if source_fs and source_fs[0] == part.get("path"):
                    fstype = source_fs[1]
            drives.append({
                "name": os.path.basename(part.get("path") or ""),
                "dev": part.get("path") or "",
                "parent": parent_path,
                "size": human_size(part.get("size") or 0),
                "label": part.get("label") or "",
                "partLabel": part.get("partlabel") or "",
                "fstype": fstype or "unknown",
                "mountpoint": mountpoint,
                "mounted": bool(mountpoint),
                "removable": parent_rm,
                "readonly": bool(part.get("ro")),
                "mountable": bool(fstype) and not mountpoint,
                "repairable": fstype in {"ntfs", "vfat", "fat32", "exfat", "ext2", "ext3", "ext4"},
                "kind": drive_kind({"rm": parent_rm}),
                "model": (parent_model or parent_vendor).strip(),
            })
    drives.sort(key=lambda d: (not d["removable"], d["name"]))
    return drives


def find_drive(dev):
    for drive in collect_drives():
        if drive["dev"] == dev:
            return drive
    return None


def cmd_list(_args):
    try:
        drives = collect_drives()
    except Exception as error:  # noqa: BLE001 - surfaced to the UI
        fail(str(error))
    ok("", drives=drives)


def cmd_mount(args):
    drive = find_drive(args.dev)
    if not drive:
        fail(_t("No encontré esa unidad.", "Could not find that drive."))
    if drive["mounted"]:
        ok(_t("Ya está montada.", "Already mounted."), mountpoint=drive["mountpoint"])
    result = run(["udisksctl", "mount", "-b", args.dev])
    if result.returncode != 0:
        stderr = result.stderr.strip() or "mount failed"
        if "dirty" in stderr.lower() or "superblock" in stderr.lower():
            stderr += " · " + _t(
                "Usa Reparar en la tarjeta de la unidad.",
                "Use Repair on the drive card.")
        fail(stderr)
    mountpoint = ""
    for line in result.stdout.splitlines():
        if " at " in line:
            mountpoint = line.split(" at ", 1)[1].strip().rstrip(".")
    refreshed = find_drive(args.dev)
    ok(_t("Montada.", "Mounted."), mountpoint=mountpoint or (refreshed or {}).get("mountpoint", ""))


def cmd_unmount(args):
    result = run(["udisksctl", "unmount", "-b", args.dev])
    if result.returncode != 0:
        fail(result.stderr.strip() or _t("No se pudo desmontar.", "Could not unmount."))
    ok(_t("Desmontada.", "Unmounted."))


def cmd_poweroff(args):
    drive = find_drive(args.dev)
    target = (drive or {}).get("parent") or args.dev
    # Unmount every mounted partition of the parent disk first.
    for candidate in collect_drives():
        if candidate["parent"] == target and candidate["mounted"]:
            run(["udisksctl", "unmount", "-b", candidate["dev"]])
    result = run(["udisksctl", "power-off", "-b", target], timeout=45)
    if result.returncode != 0:
        fail(result.stderr.strip() or _t("No se pudo apagar la unidad.", "Could not power off the drive."))
    ok(_t("Unidad extraída con seguridad. Ya puedes desconectarla.",
          "Drive safely ejected. You can unplug it now."))


def cmd_repair(args):
    drive = find_drive(args.dev)
    if not drive:
        fail(_t("No encontré esa unidad.", "Could not find that drive."))
    fstype = (drive.get("fstype") or "").lower()
    commands = {
        "ntfs": ["ntfsfix", "-d"],
        "vfat": ["fsck.fat", "-a"],
        "fat32": ["fsck.fat", "-a"],
        "exfat": ["fsck.exfat"],
        "ext4": ["fsck.ext4", "-y"],
        "ext3": ["fsck.ext3", "-y"],
        "ext2": ["fsck.ext2", "-y"],
    }
    tool = commands.get(fstype)
    if not tool:
        fail(_t("No tengo reparación automática para %s." % fstype,
                "No automatic repair available for %s." % fstype))
    if drive["mounted"] and not fstype.startswith("ntfs"):
        fail(_t("Desmonta la unidad antes de repararla.", "Unmount the drive before repairing it."))
    if not shutil.which("pkexec"):
        fail(_t("Necesito polkit (pkexec) para reparar.", "polkit (pkexec) is required to repair."))
    result = run(["pkexec"] + tool + [args.dev], timeout=120)
    output = (result.stdout or "") + (result.stderr or "")
    if result.returncode != 0:
        detail = output.strip().splitlines()
        fail(detail[-1] if detail else _t("La reparación falló.", "Repair failed."))
    if "processed successfully" in output or "clean" in output.lower() or result.returncode == 0:
        ok(_t("Reparada. Intenta montarla de nuevo.", "Repaired. Try mounting it again."))
    ok(output.strip()[:200])


def cmd_open(args):
    path = args.path
    if not path or not os.path.isdir(path):
        fail(_t("La unidad no está montada.", "The drive is not mounted."))
    result = run(["xdg-open", path], timeout=10)
    if result.returncode != 0:
        fail(_t("No se pudo abrir el gestor de archivos.", "Could not open the file manager."))
    ok(_t("Abierta.", "Opened."))


def cmd_rescan(_args):
    # Re-trigger the kernel's SCSI/NVMe discovery so freshly plugged drives show up.
    hosts = []
    for base in ("/sys/class/scsi_host",):
        if os.path.isdir(base):
            hosts = sorted(os.listdir(base))
    if hosts:
        script = "; ".join("echo '- - -' > /sys/class/scsi_host/%s/scan" % h for h in hosts)
        result = run(["pkexec", "sh", "-c", script], timeout=30)
        if result.returncode != 0:
            fail(result.stderr.strip() or _t("El reescaneo falló.", "Rescan failed."))
    ok(_t("Buscando unidades nuevas…", "Looking for new drives…"))


def main():
    parser = argparse.ArgumentParser(description="OmaDrives helper")
    parser.add_argument("--lang", default="en", choices=["es", "en"])
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("list")
    mount = sub.add_parser("mount")
    mount.add_argument("--dev", required=True)
    unmount = sub.add_parser("unmount")
    unmount.add_argument("--dev", required=True)
    poweroff = sub.add_parser("poweroff")
    poweroff.add_argument("--dev", required=True)
    repair = sub.add_parser("repair")
    repair.add_argument("--dev", required=True)
    opener = sub.add_parser("open")
    opener.add_argument("--path", required=True)
    sub.add_parser("rescan")

    args = parser.parse_args()
    global LANG
    LANG = args.lang

    handlers = {
        "list": cmd_list, "mount": cmd_mount, "unmount": cmd_unmount,
        "poweroff": cmd_poweroff, "repair": cmd_repair, "open": cmd_open,
        "rescan": cmd_rescan,
    }
    handler = handlers.get(args.command)
    if not handler:
        parser.print_help(sys.stderr)
        sys.exit(2)
    try:
        handler(args)
    except subprocess.TimeoutExpired:
        fail(_t("La operación tardó demasiado.", "The operation timed out."))
    except Exception as error:  # noqa: BLE001 - last-resort guard for the UI
        fail(str(error))


if __name__ == "__main__":
    main()
