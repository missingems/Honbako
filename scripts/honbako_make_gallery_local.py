#!/usr/bin/env python3
"""Convert Honbako's disposable screenshot gallery into readable local CBZ books.

The caller MUST terminate the simulator app before invoking this helper and must
not launch it again until the helper exits. This is never for a personal library.
Only the screenshot gallery's records are changed; original tutorial, library
ordering, existing reading history and bookmarks are preserved.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import sqlite3
import sys
import tempfile
import time
from urllib.parse import unquote, urlparse
import uuid
import xml.etree.ElementTree as ET
import zipfile

MANGADEX = "honbako.mangadex"
LOCAL = "local"
GALLERY_NAMESPACE = "honbako-original-cover-gallery/"
APPLE_EPOCH = 978307200
EXPECTED_COUNT = 50


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha256(path):
    with path.open("rb") as source:
        digest = hashlib.sha256()
        for data in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest()


def quoted_identifier(name):
    return '"' + name.replace('"', '""') + '"'


def columns(connection, table, database="main"):
    return {row[1] for row in connection.execute(
        f"PRAGMA {database}.table_info({quoted_identifier(table)})")}


def all_rows(connection, table):
    return connection.execute(
        f"SELECT * FROM {quoted_identifier(table)} ORDER BY Z_PK").fetchall()


def local_source_archive():
    # Exact representation found in existing SourceObject.customSource data.
    return plistlib.dumps({
        "$version": 100000,
        "$archiver": "NSKeyedArchiver",
        "$top": {"root": plistlib.UID(1)},
        "$objects": ["$null", b"\x02"],
    }, fmt=plistlib.FMT_BINARY, sort_keys=False)


def validate_archive(path, expected_hash):
    with zipfile.ZipFile(path) as archive:
        require(archive.namelist() == ["000-cover.png", "ComicInfo.xml"],
                f"Unexpected existing CBZ contents: {path}")
        require(archive.testzip() is None, f"Corrupt CBZ: {path}")
        require(hashlib.sha256(archive.read("000-cover.png")).hexdigest() == expected_hash,
                f"Existing CBZ does not contain the original cover: {path}")


def create_archive(path, image, title, expected_hash, created_files):
    if path.exists():
        validate_archive(path, expected_hash)
        return
    root = ET.Element("ComicInfo")
    for key, value in [
        ("Series", title),
        ("Title", "Original Cover Art"),
        ("Writer", "Honbako Originals"),
        ("Artist", "Honbako Originals"),
        ("Summary", "An original cover-art portfolio containing one generated cover image; not a full manga story."),
        ("PageCount", "1"),
        ("LanguageISO", "en"),
    ]:
        ET.SubElement(root, key).text = value
    descriptor, temporary = tempfile.mkstemp(prefix=".gallery-", suffix=".cbz", dir=path.parent)
    os.close(descriptor)
    temporary = Path(temporary)
    try:
        with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_STORED) as archive:
            archive.write(image, "000-cover.png")
            archive.writestr("ComicInfo.xml", ET.tostring(root, encoding="utf-8", xml_declaration=True))
        validate_archive(temporary, expected_hash)
        temporary.replace(path)
        created_files.append(path)
    finally:
        if temporary.exists():
            temporary.unlink()


def link_or_copy(source, destination, expected_hash, created_files):
    if destination.exists():
        require(sha256(destination) == expected_hash,
                f"Refusing to overwrite an unrelated existing file: {destination}")
        return
    try:
        os.link(source, destination)
    except OSError:
        shutil.copy2(source, destination)
    created_files.append(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("container", type=Path, help="Existing disposable simulator app data container")
    parser.add_argument("covers", type=Path, help="Original cover asset directory containing manifest.json")
    parser.add_argument("--app-stopped", action="store_true", required=True,
                        help="Assert the caller has terminated the simulator app")
    args = parser.parse_args()
    container = args.container.expanduser().resolve()
    covers_dir = args.covers.expanduser().resolve()
    require("/Library/Developer/CoreSimulator/Devices/" in str(container),
            "Only disposable CoreSimulator app containers are allowed")
    require("/Containers/Data/Application/" in str(container),
            "Expected a simulator app data container")
    documents = container / "Documents"
    stores = container / "Library/Application Support"
    primary = stores / "Aidoku.sqlite"
    registry = stores / "Local.sqlite"
    require(documents.is_dir() and primary.is_file() and registry.is_file(),
            "App data container or both existing Core Data stores are missing")
    manifest = json.loads((covers_dir / "manifest.json").read_text())
    covers = manifest["covers"]
    require(len(covers) == 12, "Expected the 12 approved original cover assets")
    require(len({cover["slug"] for cover in covers}) == len(covers), "Duplicate cover slugs")
    expected = {}
    for index in range(EXPECTED_COUNT):
        cover = covers[index % len(covers)]
        volume = index // len(covers) + 1
        key = str(uuid.uuid5(uuid.NAMESPACE_URL, GALLERY_NAMESPACE + cover["slug"] + "/" + str(volume)))
        expected[key] = (cover, volume)
        expected[f"{index+1:08x}-0000-4000-8000-000000000000"] = (cover, volume)
    for cover in covers:
        image = (covers_dir / cover["file"]).resolve()
        require(image.is_relative_to(covers_dir) and image.is_file(), "Invalid original asset path")
        require(sha256(image) == cover["sha256"], "Original asset no longer matches its manifest")

    created_files = []
    created_directories = []
    backup_dir = None
    connection = None
    databases_may_have_changed = False

    def ensure_directory(path):
        if path.exists():
            require(path.is_dir(), f"Expected a directory: {path}")
            return
        ensure_directory(path.parent)
        path.mkdir()
        created_directories.append(path)

    try:
        connection = sqlite3.connect(primary, timeout=5)
        connection.execute("ATTACH DATABASE ? AS loc", (str(registry),))
        required_main = {
            "ZMANGA": {"Z_PK", "Z_ENT", "Z_OPT", "ZID", "ZSOURCEID", "ZAUTHOR", "ZTITLE", "ZCOVER", "ZFILEINFO"},
            "ZCHAPTER": {"Z_PK", "Z_ENT", "Z_OPT", "ZMANGA", "ZID", "ZSOURCEID", "ZFILEINFO", "ZHISTORY"},
            "ZLOCALFILEINFO": {"Z_PK", "Z_ENT", "Z_OPT", "ZCHAPTER", "ZMANGA", "ZDATECREATED", "ZDATEMODIFIED", "ZPATH"},
            "ZLIBRARYMANGA": {"Z_PK", "ZMANGA"},
            "Z_PRIMARYKEY": {"Z_ENT", "Z_NAME", "Z_MAX"},
        }
        for table, required in required_main.items():
            require(required <= columns(connection, table), f"Unsupported Core Data schema for {table}")
        require({"Z_PK", "Z_ENT", "Z_OPT", "ZLISTING", "ZAPIVERSION", "ZID", "ZPATH", "ZCUSTOMSOURCE"}
                <= columns(connection, "ZSOURCE", "loc"), "Unsupported source registry schema")
        rows = connection.execute(
            "SELECT Z_PK,ZID,ZSOURCEID,ZAUTHOR,ZTITLE,ZCOVER,ZFILEINFO FROM ZMANGA WHERE ZID IN (" +
            ",".join("?" for _ in expected) + ") ORDER BY Z_PK", tuple(expected)).fetchall()
        require(len(rows) == EXPECTED_COUNT, "The expected 50 screenshot-only gallery entries are not present")
        require(connection.execute("SELECT count(*) FROM ZMANGA").fetchone()[0] <= 100,
                "Refusing to alter a large/potentially personal library")
        gallery = []
        for pk, key, source, author, title, cover_url, old_manga_file_info in rows:
            spec, volume = expected[key]
            require(source in (MANGADEX, LOCAL), "Gallery entry has an unexpected source")
            require(author == "Honbako Originals" and title == spec["title"].title() + " — Art Collection " + str(volume),
                    "Entry is not the expected original-art screenshot gallery")
            parsed = urlparse(cover_url or "")
            require(parsed.scheme == "file", "Screenshot cover is not a local file")
            seeded_image = Path(unquote(parsed.path)).resolve()
            require(seeded_image.is_relative_to(documents) and seeded_image.is_file(),
                    "Seeded cover is outside the simulator Documents directory")
            require(sha256(seeded_image) == spec["sha256"], "Seeded cover differs from original generated artwork")
            chapters = connection.execute(
                "SELECT Z_PK,ZID,ZSOURCEID,ZFILEINFO,ZHISTORY FROM ZCHAPTER WHERE ZMANGA=? ORDER BY Z_PK", (pk,)).fetchall()
            require(len(chapters) == 1, "Each gallery portfolio must have exactly one chapter")
            chapter_pk, chapter_id, chapter_source, old_chapter_file_info, history = chapters[0]
            require(chapter_source == source, "Gallery chapter and manga sources differ")
            if source == MANGADEX:
                require(history is None, "Unread screenshot data is required before converting source identity")
            linked = connection.execute("SELECT count(*) FROM ZLIBRARYMANGA WHERE ZMANGA=?", (pk,)).fetchone()[0]
            require(linked == 1, "Gallery entry is not linked once to the existing library")
            gallery.append((pk, key, chapter_pk, seeded_image, spec, old_manga_file_info, old_chapter_file_info))
        preferences_path = container / "Library/Preferences/com.missingems.honbaku.plist"
        if preferences_path.is_file():
            preferences = plistlib.loads(preferences_path.read_bytes())
            require(LOCAL not in preferences.get("Browse.disabledSources", []),
                    "The local source is disabled in this simulator; enable it before conversion")
        library_before = all_rows(connection, "ZLIBRARYMANGA")
        protected_tables = [name for name, in connection.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('ZHISTORY','ZREADINGSESSION')")]
        protected_before = {name: all_rows(connection, name) for name in protected_tables}
        tutorial_manga_before = connection.execute(
            "SELECT * FROM ZMANGA WHERE ZID NOT IN (" + ",".join("?" for _ in expected) + ") ORDER BY Z_PK",
            tuple(expected)).fetchall()
        tutorial_chapter_before = connection.execute(
            "SELECT * FROM ZCHAPTER WHERE ZMANGA NOT IN (" + ",".join("?" for _ in gallery) + ") ORDER BY Z_PK",
            tuple(row[0] for row in gallery)).fetchall()
        ensure_directory(container / "tmp")
        backup_dir = Path(tempfile.mkdtemp(prefix="HonbakoLocalGallery-backup-", dir=container / "tmp"))
        for name, database in [("Aidoku.sqlite", "main"), ("Local.sqlite", "loc")]:
            with sqlite3.connect(backup_dir / name) as backup:
                connection.backup(backup, name=database)
        (backup_dir / "README.txt").write_text(
            "Before-conversion snapshots of both stores, including committed WAL contents. "
            "Keep the app stopped if manually restoring. This backup belongs only to the disposable screenshot container.\n")
        connection.execute("BEGIN IMMEDIATE")
        source_entity = connection.execute(
            "SELECT Z_ENT,Z_MAX FROM loc.Z_PRIMARYKEY WHERE Z_NAME='Source'").fetchone()
        require(source_entity is not None, "Source entity mapping is missing")
        existing_source = connection.execute("SELECT Z_PK,ZCUSTOMSOURCE FROM loc.ZSOURCE WHERE ZID=?", (LOCAL,)).fetchall()
        require(len(existing_source) <= 1, "Duplicate local source registry entries")
        if existing_source:
            source_pk = existing_source[0][0]
            data = plistlib.loads(existing_source[0][1])
            require(data.get("$objects") == ["$null", b"\x02"], "Existing local source config is unexpected")
        else:
            source_pk = max(source_entity[1] or 0,
                            connection.execute("SELECT coalesce(max(Z_PK),0) FROM loc.ZSOURCE").fetchone()[0]) + 1
            connection.execute(
                "INSERT INTO loc.ZSOURCE (Z_PK,Z_ENT,Z_OPT,ZLISTING,ZAPIVERSION,ZID,ZPATH,ZCUSTOMSOURCE) VALUES (?,?,1,0,'0.7',?,NULL,?)",
                (source_pk, source_entity[0], LOCAL, local_source_archive()))
            connection.execute("UPDATE loc.Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='Source'", (source_pk,))
        file_entity = connection.execute("SELECT Z_ENT,Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME='LocalFileInfo'").fetchone()
        require(file_entity is not None, "LocalFileInfo entity mapping is missing")
        next_file_pk = max(file_entity[1] or 0,
                           connection.execute("SELECT coalesce(max(Z_PK),0) FROM ZLOCALFILEINFO").fetchone()[0])
        now = time.time() - APPLE_EPOCH
        archives = documents / "ScreenshotOriginalArchives"
        local_root = documents / "Local"
        ensure_directory(archives)
        ensure_directory(local_root)
        checked_archives = {}
        expected_links = []
        for manga_pk, key, chapter_pk, image, spec, old_manga_fi, old_chapter_fi in gallery:
            canonical_archive = archives / (spec["slug"] + ".cbz")
            if spec["slug"] not in checked_archives:
                create_archive(canonical_archive, image, spec["title"], spec["sha256"], created_files)
                checked_archives[spec["slug"]] = sha256(canonical_archive)
            manga_folder = local_root / key
            ensure_directory(manga_folder)
            archive = manga_folder / "chapter_1.cbz"
            link_or_copy(canonical_archive, archive, checked_archives[spec["slug"]], created_files)
            link_or_copy(image, manga_folder / "cover.png", spec["sha256"], created_files)
            manga_relative = str(manga_folder.relative_to(documents))
            chapter_relative = str(archive.relative_to(documents))
            ids = []
            for old_id, relationship, relation_pk, relative in [
                (old_manga_fi, "ZMANGA", manga_pk, manga_relative),
                (old_chapter_fi, "ZCHAPTER", chapter_pk, chapter_relative),
            ]:
                if old_id is not None:
                    record = connection.execute(
                        "SELECT ZMANGA,ZCHAPTER,ZPATH FROM ZLOCALFILEINFO WHERE Z_PK=?", (old_id,)).fetchone()
                    expected_record = (relation_pk, None, relative) if relationship == "ZMANGA" else (None, relation_pk, relative)
                    require(record == expected_record, "Refusing to overwrite unrelated LocalFileInfo metadata")
                    ids.append(old_id)
                else:
                    next_file_pk += 1
                    manga_link = relation_pk if relationship == "ZMANGA" else None
                    chapter_link = relation_pk if relationship == "ZCHAPTER" else None
                    connection.execute(
                        "INSERT INTO ZLOCALFILEINFO (Z_PK,Z_ENT,Z_OPT,ZMANGA,ZCHAPTER,ZDATECREATED,ZDATEMODIFIED,ZPATH) VALUES (?,?,1,?,?,?,?,?)",
                        (next_file_pk, file_entity[0], manga_link, chapter_link, now, now, relative))
                    ids.append(next_file_pk)
            connection.execute(
                "UPDATE ZMANGA SET ZSOURCEID=?,ZFILEINFO=?,Z_OPT=coalesce(Z_OPT,0)+1 WHERE Z_PK=?",
                (LOCAL, ids[0], manga_pk))
            connection.execute(
                "UPDATE ZCHAPTER SET ZSOURCEID=?,ZFILEINFO=?,Z_OPT=coalesce(Z_OPT,0)+1 WHERE Z_PK=?",
                (LOCAL, ids[1], chapter_pk))
            expected_links.append((manga_pk, chapter_pk, ids[0], ids[1], manga_relative, chapter_relative))
        connection.execute("UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_NAME='LocalFileInfo'", (next_file_pk,))
        require(all_rows(connection, "ZLIBRARYMANGA") == library_before, "Existing library ordering changed")
        for name, before in protected_before.items():
            require(all_rows(connection, name) == before, f"Existing {name} data changed")
        require(connection.execute(
            "SELECT * FROM ZMANGA WHERE ZID NOT IN (" + ",".join("?" for _ in expected) + ") ORDER BY Z_PK",
            tuple(expected)).fetchall() == tutorial_manga_before, "Tutorial/non-gallery manga changed")
        require(connection.execute(
            "SELECT * FROM ZCHAPTER WHERE ZMANGA NOT IN (" + ",".join("?" for _ in gallery) + ") ORDER BY Z_PK",
            tuple(row[0] for row in gallery)).fetchall() == tutorial_chapter_before, "Tutorial/non-gallery chapters changed")
        for manga_pk, chapter_pk, manga_fi, chapter_fi, folder, path in expected_links:
            require(connection.execute("SELECT ZSOURCEID,ZFILEINFO FROM ZMANGA WHERE Z_PK=?", (manga_pk,)).fetchone() == (LOCAL, manga_fi), "Invalid local manga linkage")
            require(connection.execute("SELECT ZSOURCEID,ZFILEINFO,ZMANGA FROM ZCHAPTER WHERE Z_PK=?", (chapter_pk,)).fetchone() == (LOCAL, chapter_fi, manga_pk), "Invalid local chapter linkage")
            require(connection.execute("SELECT ZMANGA,ZCHAPTER,ZPATH FROM ZLOCALFILEINFO WHERE Z_PK=?", (manga_fi,)).fetchone() == (manga_pk, None, folder), "Invalid manga file metadata")
            require(connection.execute("SELECT ZMANGA,ZCHAPTER,ZPATH FROM ZLOCALFILEINFO WHERE Z_PK=?", (chapter_fi,)).fetchone() == (None, chapter_pk, path), "Invalid chapter archive metadata")
        require(connection.execute("PRAGMA main.quick_check").fetchone()[0] == "ok", "Main database failed quick_check")
        require(connection.execute("PRAGMA loc.quick_check").fetchone()[0] == "ok", "Registry database failed quick_check")
        databases_may_have_changed = True
        connection.commit()
        connection.execute("PRAGMA main.wal_checkpoint(TRUNCATE)")
        connection.execute("PRAGMA loc.wal_checkpoint(TRUNCATE)")
        connection.close()
        connection = None
        result = {
            "status": "converted",
            "source": LOCAL,
            "readable_art_collection_books": len(gallery),
            "pages_per_book": 1,
            "unique_original_covers": len(checked_archives),
            "library_order_and_existing_bookmarks_preserved": True,
            "tutorial_unchanged": True,
            "backup_directory": str(backup_dir),
            "storage_note": "Repeated portfolios use hard links to twelve canonical CBZs when supported. Remove this disposable capture app after screenshots to clean gallery files and backups.",
        }
        print(json.dumps(result, indent=2))
        return 0
    except Exception:
        if connection is not None:
            try:
                connection.rollback()
            except sqlite3.Error:
                pass
            connection.close()
            connection = None
        # A backup restore also covers a rare partial attached-database commit.
        if databases_may_have_changed and backup_dir is not None:
            for name, live in [("Aidoku.sqlite", primary), ("Local.sqlite", registry)]:
                with sqlite3.connect(backup_dir / name) as before, sqlite3.connect(live) as target:
                    before.backup(target)
                    target.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        for path in reversed(created_files):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        for path in reversed(created_directories):
            try:
                path.rmdir()
            except OSError:
                pass
        if backup_dir is not None:
            print("Rollback backup retained at " + str(backup_dir), file=sys.stderr)
        raise


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print("Local gallery conversion failed: " + str(error), file=sys.stderr)
        raise SystemExit(1)
