"""Фото сотрудников: проверка, ресайз и файл в каталоге PHOTO_DIR.

В БД лежат только метаданные (см. `app/models/employee_photo.py`), сам файл —
на томе. Здесь два правила, которые нельзя обойти:

1. имя файла генерируем сами (`token_hex`), а не берём из загруженного файла:
   иначе браузерное `../../etc/passwd` стало бы путём записи;
2. в базу пишем только имя, а `photo_path()` проверяет, что в нём нет
   разделителей пути — значение из БД тоже не должно уметь выйти из каталога.
"""
import hashlib
import io
import secrets
from pathlib import Path

from fastapi import HTTPException, UploadFile, status
from PIL import Image, ImageOps, UnidentifiedImageError

from app.core.config import settings

ALLOWED_TYPES = {"image/jpeg", "image/png", "image/webp"}
MAX_SIDE = (400, 500)  # вписываем в портрет без искажений пропорций
JPEG_QUALITY = 85
# Предел на распаковку: 40 Мп. Картинка 20000×20000 весит мегабайты, но в
# памяти при распаковке занимает гигабайты («image bomb»).
MAX_PIXELS = 40_000_000


def photos_dir() -> Path:
    """Каталог фото (создаётся при первом обращении)."""
    path = Path(settings.PHOTO_DIR)
    path.mkdir(parents=True, exist_ok=True)
    return path


def photo_path(filename: str) -> Path:
    """Путь к файлу по имени из БД; имя не должно быть путём."""
    if not filename or "/" in filename or "\\" in filename or filename.startswith("."):
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Некорректное имя файла фото",
        )
    return photos_dir() / filename


async def store_employee_photo(upload: UploadFile) -> tuple[str, str, int, str]:
    """Проверяет, приводит к портрету 400×500 в JPEG и сохраняет файл.

    Возвращает (имя файла, mime, размер в байтах, sha256) для записи в БД.
    """
    if upload.content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Фото должно быть в формате JPEG, PNG или WebP",
        )

    raw = await upload.read()
    if not raw:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Файл пустой")

    limit = settings.PHOTO_MAX_MB * 1024 * 1024
    if len(raw) > limit:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Файл больше {settings.PHOTO_MAX_MB} МБ",
        )

    try:
        with Image.open(io.BytesIO(raw)) as image:
            if image.width * image.height > MAX_PIXELS:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Слишком большое изображение — уменьшите фото",
                )
            # Телефоны пишут поворот в EXIF: без этого портрет ляжет боком
            image = ImageOps.exif_transpose(image)
            image.thumbnail(MAX_SIDE, Image.LANCZOS)
            prepared = image.convert("RGB")
            buffer = io.BytesIO()
            # Метаданные (EXIF, геометки) в файл не попадают: сохраняем только пиксели
            prepared.save(buffer, format="JPEG", quality=JPEG_QUALITY, optimize=True)
    except UnidentifiedImageError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Файл не является изображением",
        ) from exc

    data = buffer.getvalue()
    filename = f"{secrets.token_hex(16)}.jpg"
    (photos_dir() / filename).write_bytes(data)

    return filename, "image/jpeg", len(data), hashlib.sha256(data).hexdigest()


def delete_photo_file(filename: str) -> None:
    """Удаляет файл фото; отсутствие файла не считается ошибкой."""
    photo_path(filename).unlink(missing_ok=True)
