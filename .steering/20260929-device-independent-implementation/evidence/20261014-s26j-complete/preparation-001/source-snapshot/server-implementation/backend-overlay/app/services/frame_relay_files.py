"""No-follow, exclusive, server-named files; never replace a saved original."""
from contextlib import contextmanager
import hashlib
import os
from pathlib import PurePosixPath
import stat

from app.repositories.frame_relay_storage import StorageError


BLOCK = 1024 * 1024


@contextmanager
def parent(root, relative, *, create=False):
    parts = PurePosixPath(relative).parts
    if not parts or PurePosixPath(relative).is_absolute() or any(p in (".", "..", "") for p in parts):
        raise StorageError("storage_path_invalid")
    descriptors = []
    try:
        fd = os.open(root.resolve(strict=True), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        descriptors.append(fd)
        for component in parts[:-1]:
            if create:
                try:
                    os.mkdir(component, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            fd = os.open(component, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            descriptors.append(fd)
        yield fd, parts[-1]
    finally:
        for fd in reversed(descriptors):
            os.close(fd)


def fingerprint(metadata):
    if not stat.S_ISREG(metadata.st_mode):
        raise StorageError("storage_file_invalid")
    return [metadata.st_dev, metadata.st_ino, metadata.st_size, metadata.st_mtime_ns, metadata.st_ctime_ns]


def current_fingerprint(root, relative):
    with parent(root, relative) as (directory, name):
        return fingerprint(os.stat(name, dir_fd=directory, follow_symlinks=False))


@contextmanager
def exclusive_writer(root, relative):
    with parent(root, relative, create=True) as (directory, name):
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        with os.fdopen(descriptor, "wb") as stream:
            yield stream
            stream.flush()
            os.fsync(stream.fileno())
        os.fsync(directory)


def read_all(root, relative, *, consume=None, fault=None):
    """Open a new FD and read through EOF; count/hash independently of assembly."""
    with parent(root, relative) as (directory, name):
        descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        with os.fdopen(descriptor, "rb") as stream:
            before = fingerprint(os.fstat(stream.fileno()))
            digest = hashlib.sha256()
            count = 0
            while block := stream.read(BLOCK):
                count += len(block)
                digest.update(block)
                if consume is not None:
                    consume(block)
                if fault is not None:
                    fault("read_block")
            after = fingerprint(os.fstat(stream.fileno()))
        if before != after or before != current_fingerprint(root, relative) or count != before[2]:
            raise StorageError("storage_file_changed")
    return {"sha256": digest.hexdigest(), "byte_count": count, "fingerprint": before}


def publish(root, source, target):
    with parent(root, source) as (source_dir, source_name), parent(root, target, create=True) as (target_dir, target_name):
        fingerprint(os.stat(source_name, dir_fd=source_dir, follow_symlinks=False))
        try:
            os.link(source_name, target_name, src_dir_fd=source_dir, dst_dir_fd=target_dir,
                    follow_symlinks=False)
            created = True
        except FileExistsError:
            fingerprint(os.stat(target_name, dir_fd=target_dir, follow_symlinks=False))
            created = False
        os.fsync(target_dir)
        return created


def remove_owned(root, relative):
    try:
        with parent(root, relative) as (directory, name):
            fingerprint(os.stat(name, dir_fd=directory, follow_symlinks=False))
            os.unlink(name, dir_fd=directory)
            os.fsync(directory)
    except FileNotFoundError:
        pass
