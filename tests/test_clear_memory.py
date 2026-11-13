"""Unit tests for EEPROM measurement wipe / index reset."""

from __future__ import annotations

import asyncio
from dataclasses import replace
from unittest.mock import AsyncMock, MagicMock, patch

from custom_components.omron.omron_ble.devices import get_device_config
from custom_components.omron.omron_ble.omron_driver import OmronDeviceDriver


class TestClearStoredRecords:
    def test_writes_ff_and_resets_index_for_hem7142t2(self) -> None:
        config = get_device_config("HEM-7142T2")
        driver = OmronDeviceDriver(config)
        transport = MagicMock()
        transport.unlock = AsyncMock()
        written: list[tuple[int, bytes]] = []

        async def fake_write(addr: int, data: bytearray, block_size: int = 0x08) -> None:
            written.append((addr, bytes(data)))

        transport.write_memory_range = AsyncMock(side_effect=fake_write)
        transport.read_memory_range = AsyncMock(
            return_value=bytearray(b"\x06\x00\x00\x00\x02\x00\x00\x00" + b"\x00" * 8)
        )

        with patch(
            "custom_components.omron.omron_ble.omron_driver.asyncio.sleep",
            new_callable=AsyncMock,
        ):
            bytes_written = asyncio.run(driver.clear_stored_records(transport))

        assert bytes_written == 14 * 0x0E
        assert written[0][0] == 0x02E8
        assert written[0][1] == bytes([0xFF] * (14 * 0x0E))
        # Index reset uses the settings write mirror, not the read address.
        assert written[1][0] == 0x02A4
        index = written[1][1]
        assert index[0:2] == (0x8000).to_bytes(2, "little")
        assert index[4:6] == (0).to_bytes(2, "little")
        transport.unlock.assert_awaited()

    def test_skips_index_without_settings_write(self) -> None:
        config = replace(get_device_config("HEM-7142T2"), settings_write_address=None)
        driver = OmronDeviceDriver(config)
        transport = MagicMock()
        transport.unlock = AsyncMock()
        transport.write_memory_range = AsyncMock()
        transport.read_memory_range = AsyncMock()

        with patch(
            "custom_components.omron.omron_ble.omron_driver.asyncio.sleep",
            new_callable=AsyncMock,
        ):
            bytes_written = asyncio.run(driver.clear_stored_records(transport))

        assert bytes_written == 14 * 0x0E
        transport.write_memory_range.assert_awaited_once()
        transport.read_memory_range.assert_not_awaited()
