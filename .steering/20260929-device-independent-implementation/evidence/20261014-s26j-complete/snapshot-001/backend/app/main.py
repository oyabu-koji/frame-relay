from contextlib import asynccontextmanager, closing

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.api.assets import router as assets_router
from app.api.capabilities import router as capabilities_router
from app.api.health import router as health_router
from app.api.presets import router as presets_router
from app.api.renditions import router as renditions_router
from app.api.registrations import router as registrations_router
from app.api.frame_relay_storage import router as storage_router
from app.repositories.frame_relay_storage import StorageError as FrameRelayStorageError
from app.repositories.registrations import RegistrationError
from app.api.registrations import _error as registration_error_response
import sqlite3
from app.api.upload_sessions import router as upload_sessions_router
from app.core.settings import load_settings
from app.db.connection import connect
from app.db.migrations import run_migrations
from app.db.frame_relay_migrations import run_frame_relay_migrations
from app.services.processed_result_backfill import backfill_eligible_processed_results
from app.services.storage import initialize_storage
from app.services.initial_release_guard import (
    assert_generated_apple_log_conversion_disabled,
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = load_settings()
    assert_generated_apple_log_conversion_disabled(settings)
    initialize_storage(settings.media_root)
    with closing(connect(settings.database_path, settings.sqlite_busy_timeout_ms)) as conn:
        run_migrations(conn)
        run_frame_relay_migrations(conn)
    backfill_eligible_processed_results(settings=settings)
    yield


app = FastAPI(title="MediaVault Backend", lifespan=lifespan)


@app.exception_handler(FrameRelayStorageError)
async def frame_relay_storage_error(_request: Request, error: FrameRelayStorageError):
    return JSONResponse(status_code=409, content={"code": error.code, "retryable": False},
                        headers={"Cache-Control": "no-store"})


@app.exception_handler(RegistrationError)
async def frame_relay_registration_error(_request: Request, error: RegistrationError):
    return registration_error_response(error)


@app.exception_handler(sqlite3.DatabaseError)
async def frame_relay_database_error(_request: Request, _error: sqlite3.DatabaseError):
    return JSONResponse(status_code=503, content={"code": "storage_unavailable", "retryable": True},
                        headers={"Cache-Control": "no-store"})


app.include_router(storage_router)


@app.exception_handler(RequestValidationError)
async def validation_error_response(_request: Request, _error: RequestValidationError) -> JSONResponse:
    """Do not reflect upload metadata, paths, or token-adjacent request details."""
    return JSONResponse(
        status_code=422,
        content={"code": "validation_error", "retryable": False},
    )


app.include_router(health_router)
app.include_router(assets_router)
app.include_router(upload_sessions_router)
app.include_router(capabilities_router)
app.include_router(presets_router)
app.include_router(renditions_router)

app.include_router(registrations_router)
