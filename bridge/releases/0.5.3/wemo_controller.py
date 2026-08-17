from __future__ import annotations

import threading
import time
from dataclasses import dataclass
from typing import Any

import pywemo

from . import storage


@dataclass
class DeviceInfo:
    id: str
    name: str
    model: str
    state: int | None


class WemoController:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._devices: dict[str, Any] = {}
        self._last_discovery = 0.0
        self._last_error = ""
        self._last_known_state: dict[str, int] = {}

    @staticmethod
    def _device_id(device: Any) -> str:
        for attr in ("udn", "serialnumber", "serial_number"):
            value = getattr(device, attr, None)
            if value:
                return str(value)
        return f"{device.__class__.__name__}:{getattr(device, 'name', 'Wemo')}"

    @staticmethod
    def _model(device: Any) -> str:
        for attr in ("model_name", "model", "model_number"):
            value = getattr(device, attr, None)
            if value:
                return str(value)
        return device.__class__.__name__.replace("Device", "")

    def discover(self, force: bool = False) -> list[DeviceInfo]:
        with self._lock:
            if not force and self._devices and (time.time() - self._last_discovery) < 20:
                return self._infos()
            try:
                found = pywemo.discover_devices()
                self._devices = {self._device_id(d): d for d in found}
                self._last_discovery = time.time()
                self._last_error = ""
            except Exception as exc:
                self._last_error = str(exc)
            return self._infos()

    def _infos(self) -> list[DeviceInfo]:
        infos: list[DeviceInfo] = []
        for device_id, device in self._devices.items():
            state: int | None = None
            try:
                observed = int(device.get_state(force_update=True))
                if observed in (0, 1):
                    state = observed
                    self._last_known_state[device_id] = observed
                else:
                    state = self._last_known_state.get(device_id)
            except Exception:
                state = self._last_known_state.get(device_id)
            infos.append(DeviceInfo(id=device_id, name=str(getattr(device, "name", "Wemo")), model=self._model(device), state=state))
        return infos

    def selected(self) -> Any | None:
        selected_id = str(storage.get_setting("selected_device_id") or "")
        if not self._devices:
            self.discover(force=True)
        if selected_id and selected_id in self._devices:
            return self._devices[selected_id]
        if len(self._devices) == 1:
            device_id, device = next(iter(self._devices.items()))
            storage.set_setting("selected_device_id", device_id)
            return device
        return None

    def select(self, device_id: str) -> None:
        self.discover(force=True)
        if device_id not in self._devices:
            raise ValueError("That Wemo device is not currently discoverable.")
        storage.set_setting("selected_device_id", device_id)

    def state(self) -> int | None:
        device = self.selected()
        if device is None:
            return None
        device_id = self._device_id(device)
        try:
            observed = int(device.get_state(force_update=True))
            if observed in (0, 1):
                self._last_known_state[device_id] = observed
                self._last_error = ""
                return observed
            return self._last_known_state.get(device_id)
        except Exception as exc:
            self._last_error = str(exc)
            return self._last_known_state.get(device_id)

    def set_power(self, on: bool) -> int:
        with self._lock:
            device = self.selected()
            if device is None:
                raise RuntimeError("No Wemo device is selected or discoverable.")
            try:
                if on:
                    device.on()
                else:
                    device.off()
                commanded = 1 if on else 0
                self._last_known_state[self._device_id(device)] = commanded
                self._last_error = ""
                return commanded
            except Exception as exc:
                self._last_error = str(exc)
                raise RuntimeError(f"Wemo command failed: {exc}") from exc

    def feed_pulse(self, seconds: float) -> None:
        seconds = max(0.2, min(float(seconds), 30.0))
        self.set_power(True)
        try:
            time.sleep(seconds)
        finally:
            try:
                self.set_power(False)
            except Exception:
                pass

    @property
    def last_error(self) -> str:
        return self._last_error
