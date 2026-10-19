"""No-follow, exclusive, server-named files; never replace a saved original."""
from contextlib import contextmanager
import hashlib
import os
import re
from pathlib import PurePosixPath
import stat

from app.repositories.frame_relay_storage import StorageError


BLOCK = 1024 * 1024
SEALED_PREFIX = "publications/frame-relay/"


def _not_sealed(relative):
    if str(relative).startswith(SEALED_PREFIX):
        raise StorageError("publication_artifact_is_sealed")


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
    _not_sealed(relative)
    with _exclusive_writer(root, relative) as stream:
        yield stream


@contextmanager
def _exclusive_writer(root, relative):
    with parent(root, relative, create=True) as (directory, name):
        descriptor = os.open(name, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                             0o600, dir_fd=directory)
        with os.fdopen(descriptor, "wb") as stream:
            yield stream
            stream.flush()
            os.fsync(stream.fileno())
        os.fsync(directory)


@contextmanager
def sealed_writer(root, relative):
    """The publication owner creates a fresh inode; it never adopts a hard link.

    This is an application-writer ownership boundary, not protection from an
    external process with permission to chmod/write the same inode.
    """
    if re.fullmatch(r"publications/frame-relay/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.media", relative) is None:
        raise StorageError("storage_path_invalid")
    with _exclusive_writer(root, relative) as stream:
        yield stream
        stream.flush()
        os.fsync(stream.fileno())
        os.fchmod(stream.fileno(), 0o400)


@contextmanager
def verified_reader(root, relative, *, sha256, byte_count, expected_fingerprint, fault=None):
    """Full read outside the writer; caller retains this FD through commit/body."""
    with parent(root, relative) as (directory, name):
        descriptor = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=directory)
        with os.fdopen(descriptor, "rb") as stream:
            before = fingerprint(os.fstat(stream.fileno()))
            if before != expected_fingerprint:
                raise StorageError("storage_file_changed")
            digest, count = hashlib.sha256(), 0
            while block := stream.read(BLOCK):
                digest.update(block)
                count += len(block)
                if fault is not None:
                    fault("read_block")
                if count > byte_count:
                    raise StorageError("storage_file_changed")
            if (count != byte_count or digest.hexdigest() != sha256 or
                    before != fingerprint(os.fstat(stream.fileno())) or
                    before != current_fingerprint(root, relative)):
                raise StorageError("storage_file_changed")
            stream.seek(0)
            yield stream, before


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
    _not_sealed(source)
    _not_sealed(target)
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
    _not_sealed(relative)
    try:
        with parent(root, relative) as (directory, name):
            fingerprint(os.stat(name, dir_fd=directory, follow_symlinks=False))
            os.unlink(name, dir_fd=directory)
            os.fsync(directory)
    except FileNotFoundError:
        pass
