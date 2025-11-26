#!/usr/bin/env python3
"""
KS Smart LED Control Menu - Interactive BLE controller for KS LED devices.

Supports:
- Multiple device types (KS01-06, ceiling/floor lamps)
- RGB color control with presets
- Brightness adjustment (floor lamps)
- Device nicknames for easy identification
- Custom color creation and saving

Usage:
    python3 led_menu.py

Requirements:
    pip install bleak
"""
import asyncio
import json
import os
import sys
from pathlib import Path

try:
    from bleak import BleakClient, BleakScanner
except ImportError:
    print("❌ Please install bleak: pip install bleak")
    sys.exit(1)

# UUID template
UUID_TEMPLATE = "0000%s-0000-1000-8000-00805f9b34fb"

# Device mappings
DEVICE_MAPPINGS = {
    "KS03-": {"service": "FFF0", "write": "FFF3", "type": "ceiling"},
    "KS03~": {"service": "AFD0", "write": "AFD1", "type": "floor"},
    "KS04-": {"service": "FFF0", "write": "FFF3", "type": "ceiling"},
    "KS01-": {"service": "AE00", "write": "AE01", "type": "ceiling"},
    "KS02-": {"service": "AE00", "write": "AE01", "type": "ceiling"},
}

# Presets file
PRESETS_FILE = Path.home() / ".ks_led_presets.json"
DEVICES_FILE = Path.home() / ".ks_led_devices.json"

# Default presets
DEFAULT_PRESETS = {
    "Warm White": {"r": 255, "g": 147, "b": 41},
    "Cool White": {"r": 201, "g": 226, "b": 255},
    "Daylight": {"r": 255, "g": 250, "b": 244},
    "Red": {"r": 255, "g": 0, "b": 0},
    "Green": {"r": 0, "g": 255, "b": 0},
    "Blue": {"r": 0, "g": 0, "b": 255},
    "Purple": {"r": 128, "g": 0, "b": 128},
    "Cyan": {"r": 0, "g": 255, "b": 255},
    "Yellow": {"r": 255, "g": 255, "b": 0},
    "Orange": {"r": 255, "g": 165, "b": 0},
}

# Color codes for terminal
class Colors:
    RESET = "\033[0m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    
    # Standard colors
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    MAGENTA = "\033[95m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    GRAY = "\033[90m"
    
    @staticmethod
    def rgb(r, g, b):
        """Return RGB color escape code."""
        return f"\033[38;2;{r};{g};{b}m"

def load_presets():
    """Load presets from file or return defaults."""
    if PRESETS_FILE.exists():
        try:
            with open(PRESETS_FILE, 'r') as f:
                return json.load(f)
        except Exception:
            pass
    return DEFAULT_PRESETS.copy()

def save_presets(presets):
    """Save presets to file."""
    try:
        with open(PRESETS_FILE, 'w') as f:
            json.dump(presets, f, indent=2)
    except Exception as e:
        print(f"⚠️  Could not save presets: {e}")

def load_devices():
    """Load device nicknames from file."""
    if DEVICES_FILE.exists():
        try:
            with open(DEVICES_FILE, 'r') as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_devices(devices_dict):
    """Save device nicknames to file."""
    try:
        with open(DEVICES_FILE, 'w') as f:
            json.dump(devices_dict, f, indent=2)
    except Exception as e:
        print(f"⚠️  Could not save devices: {e}")

def get_device_display_name(addr, name, nicknames):
    """Get display name for device (nickname if available, else real name)."""
    if addr in nicknames and nicknames[addr]:
        return f"{nicknames[addr]} ({name})"
    return name

def build_on_off_cmd(is_on: bool) -> bytes:
    """Build ON/OFF command (from CmdFloor.getTopOn)."""
    return bytes.fromhex("5BF001B5" if is_on else "5B0F01B5")

def build_color_cmd(r: int, g: int, b: int, device_type: str = "ceiling", brightness: int = 255) -> bytes:
    """
    Build RGB color command for KS LED devices.
    
    Args:
        r: Red value (0-255)
        g: Green value (0-255)
        b: Blue value (0-255)
        device_type: "ceiling" or "floor" lamp type
        brightness: Brightness value (0-255)
    
    Returns:
        Bytes command to send to device
    
    Command formats:
        Ceiling: 7E070503RRGGBB00EF
        Floor:   5A0001RRGGBB00BB00A5 (with brightness control)
    """
    if device_type == "floor":
        rgb_hex = f"{r:02X}{g:02X}{b:02X}"
        brightness_hex = f"{brightness:02X}"
        cmd_str = f"5A0001{rgb_hex}00{brightness_hex}00A5"
    else:
        rgb_hex = f"{r:02X}{g:02X}{b:02X}"
        cmd_str = f"7E070503{rgb_hex}00EF"
    
    return bytes.fromhex(cmd_str)

async def scan_devices(timeout=8.0):
    """Scan for KS devices and return list of (address, name, prefix)."""
    devices = []
    found = await BleakScanner.discover(timeout=timeout)
    
    for dev in found:
        name = dev.name or ""
        for prefix in DEVICE_MAPPINGS.keys():
            if name.startswith(prefix):
                devices.append((dev.address, name, prefix))
                break
    
    return devices

async def write_command(address: str, service_short: str, char_short: str, payload: bytes):
    """Write command to BLE device."""
    service_uuid = UUID_TEMPLATE % service_short
    char_uuid = UUID_TEMPLATE % char_short
    
    client = BleakClient(address)
    try:
        await client.connect()
        if not client.is_connected:
            raise RuntimeError("Failed to connect")
        
        await asyncio.sleep(0.3)
        
        # Try write without response first (preferred for KS devices)
        try:
            await client.write_gatt_char(char_uuid, payload, response=False)
        except Exception:
            # Fallback to write with response
            await client.write_gatt_char(char_uuid, payload, response=True)
        
        await asyncio.sleep(0.2)
    finally:
        if client.is_connected:
            try:
                await client.disconnect()
            except Exception:
                pass

def clear_screen():
    """Clear terminal screen."""
    os.system('clear' if os.name != 'nt' else 'cls')

def print_header():
    """Print fancy header."""
    clear_screen()
    print(f"\n{Colors.BOLD}{Colors.CYAN}╔═══════════════════════════════════════════╗{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.CYAN}║     💡 KS Smart LED Control Menu 💡       ║{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.CYAN}╚═══════════════════════════════════════════╝{Colors.RESET}\n")

def print_device_list(devices, selected_idx, nicknames=None):
    """Print device list with selection."""
    if nicknames is None:
        nicknames = {}
    print(f"{Colors.BOLD}Available Devices:{Colors.RESET}\n")
    for i, (addr, name, prefix) in enumerate(devices):
        marker = f"{Colors.GREEN}►{Colors.RESET}" if i == selected_idx else " "
        color = Colors.GREEN if i == selected_idx else Colors.GRAY
        display_name = get_device_display_name(addr, name, nicknames)
        print(f"  {marker} {color}{i+1}. {display_name} ({addr}){Colors.RESET}")
    print()

def print_menu(device_name):
    """Print main menu options."""
    print(f"{Colors.DIM}Device: {Colors.BOLD}{device_name}{Colors.RESET}\n")
    print(f"{Colors.BOLD}Main Menu:{Colors.RESET}\n")
    print(f"  {Colors.YELLOW}1{Colors.RESET}. Turn ON")
    print(f"  {Colors.YELLOW}2{Colors.RESET}. Turn OFF")
    print(f"  {Colors.YELLOW}3{Colors.RESET}. Color Presets")
    print(f"  {Colors.YELLOW}4{Colors.RESET}. Custom RGB Color")
    print(f"  {Colors.YELLOW}5{Colors.RESET}. Brightness Control")
    print(f"  {Colors.YELLOW}6{Colors.RESET}. Manage Presets")
    print(f"  {Colors.YELLOW}7{Colors.RESET}. Set Device Nickname")
    print(f"  {Colors.YELLOW}8{Colors.RESET}. Change Device")
    print(f"  {Colors.RED}q{Colors.RESET}. Quit")
    print()

def print_presets(presets):
    """Print color presets with preview."""
    print(f"\n{Colors.BOLD}Color Presets:{Colors.RESET}\n")
    
    items = list(presets.items())
    for i, (name, rgb) in enumerate(items, 1):
        r, g, b = rgb['r'], rgb['g'], rgb['b']
        color_preview = Colors.rgb(r, g, b)
        print(f"  {Colors.YELLOW}{i:2d}{Colors.RESET}. {color_preview}█████{Colors.RESET} {name} (R:{r} G:{g} B:{b})")
    
    print(f"\n  {Colors.GRAY}0{Colors.RESET}. Back to main menu")
    print()

def get_input(prompt, valid_choices=None):
    """Get user input with optional validation."""
    while True:
        choice = input(f"{Colors.BOLD}{prompt}{Colors.RESET}").strip().lower()
        if valid_choices is None or choice in valid_choices:
            return choice
        print(f"{Colors.RED}Invalid choice. Try again.{Colors.RESET}")

async def send_command(device, payload, action_name, is_color=False):
    """Send command to device with visual feedback."""
    addr, name, prefix = device
    mapping = DEVICE_MAPPINGS[prefix]
    
    print(f"\n{Colors.BLUE}⏳ Sending {action_name}...{Colors.RESET}")
    
    try:
        if is_color:
            # For color commands, keep connection open for ON + color sequence
            char_uuid = UUID_TEMPLATE % mapping["write"]
            
            client = BleakClient(addr)
            await client.connect()
            await asyncio.sleep(0.3)
            
            # Send ON command first
            on_cmd = build_on_off_cmd(True)
            await client.write_gatt_char(char_uuid, on_cmd, response=False)
            await asyncio.sleep(0.5)
            
            # Send color command on same connection
            await client.write_gatt_char(char_uuid, payload, response=False)
            await asyncio.sleep(0.2)
            
            await client.disconnect()
        else:
            # Regular commands use standard write
            await write_command(addr, mapping["service"], mapping["write"], payload)
        
        print(f"{Colors.GREEN}✓ {action_name} sent successfully!{Colors.RESET}")
    except Exception as e:
        print(f"{Colors.RED}✗ Failed: {e}{Colors.RESET}")
    
    await asyncio.sleep(1)

async def color_preset_menu(device, presets):
    """Handle color preset selection."""
    addr, name, prefix = device
    mapping = DEVICE_MAPPINGS[prefix]
    device_type = mapping.get("type", "ceiling")
    
    while True:
        print_header()
        print_presets(presets)
        
        choice = get_input("Select preset (number or 0 to go back): ")
        
        if choice == '0':
            break
        
        try:
            idx = int(choice) - 1
            items = list(presets.items())
            if 0 <= idx < len(items):
                name, rgb = items[idx]
                r, g, b = rgb['r'], rgb['g'], rgb['b']
                cmd = build_color_cmd(r, g, b, device_type)
                await send_command(device, cmd, f"{name} color", is_color=True)
            else:
                print(f"{Colors.RED}Invalid preset number{Colors.RESET}")
                await asyncio.sleep(1)
        except ValueError:
            print(f"{Colors.RED}Please enter a number{Colors.RESET}")
            await asyncio.sleep(1)

async def custom_color_menu(device):
    """Handle custom RGB color input."""
    addr, name, prefix = device
    mapping = DEVICE_MAPPINGS[prefix]
    device_type = mapping.get("type", "ceiling")
    
    print_header()
    print(f"{Colors.BOLD}Custom RGB Color{Colors.RESET}\n")
    print(f"{Colors.DIM}Enter RGB values (0-255){Colors.RESET}\n")
    
    try:
        r = int(input(f"{Colors.RED}Red (0-255): {Colors.RESET}").strip())
        g = int(input(f"{Colors.GREEN}Green (0-255): {Colors.RESET}").strip())
        b = int(input(f"{Colors.BLUE}Blue (0-255): {Colors.RESET}").strip())
        
        if not all(0 <= x <= 255 for x in (r, g, b)):
            print(f"{Colors.RED}Values must be between 0-255{Colors.RESET}")
            await asyncio.sleep(2)
            return
        
        # Show preview
        color_preview = Colors.rgb(r, g, b)
        print(f"\n{Colors.BOLD}Preview:{Colors.RESET} {color_preview}█████████{Colors.RESET} (R:{r} G:{g} B:{b})\n")
        
        confirm = get_input("Send this color? (y/n): ", ['y', 'n', 'yes', 'no'])
        if confirm in ['y', 'yes']:
            cmd = build_color_cmd(r, g, b, device_type)
            await send_command(device, cmd, "custom color", is_color=True)
            
            # Offer to save as preset
            save = get_input("Save as preset? (y/n): ", ['y', 'n', 'yes', 'no'])
            if save in ['y', 'yes']:
                name = input(f"{Colors.BOLD}Preset name: {Colors.RESET}").strip()
                if name:
                    presets = load_presets()
                    presets[name] = {"r": r, "g": g, "b": b}
                    save_presets(presets)
                    print(f"{Colors.GREEN}✓ Saved as '{name}'{Colors.RESET}")
                    await asyncio.sleep(1.5)
    
    except ValueError:
        print(f"{Colors.RED}Invalid number{Colors.RESET}")
        await asyncio.sleep(2)
    except KeyboardInterrupt:
        print()

async def brightness_menu(device):
    """Handle brightness adjustment."""
    addr, name, prefix = device
    mapping = DEVICE_MAPPINGS[prefix]
    device_type = mapping.get("type", "ceiling")
    
    print_header()
    print(f"{Colors.BOLD}Brightness Control{Colors.RESET}\n")
    print(f"{Colors.DIM}Enter brightness (0-255, or use presets){Colors.RESET}\n")
    print(f"  {Colors.YELLOW}1{Colors.RESET}. 25% (64)")
    print(f"  {Colors.YELLOW}2{Colors.RESET}. 50% (128)")
    print(f"  {Colors.YELLOW}3{Colors.RESET}. 75% (192)")
    print(f"  {Colors.YELLOW}4{Colors.RESET}. 100% (255)")
    print(f"  {Colors.YELLOW}5{Colors.RESET}. Custom value")
    print(f"  {Colors.GRAY}0{Colors.RESET}. Back to main menu\n")
    
    choice = get_input("Choose option: ").strip()
    
    if choice == '0':
        return
    
    brightness = None
    if choice == '1':
        brightness = 64
    elif choice == '2':
        brightness = 128
    elif choice == '3':
        brightness = 192
    elif choice == '4':
        brightness = 255
    elif choice == '5':
        try:
            brightness = int(input(f"{Colors.BOLD}Brightness (0-255): {Colors.RESET}").strip())
            if not 0 <= brightness <= 255:
                print(f"{Colors.RED}Value must be between 0-255{Colors.RESET}")
                await asyncio.sleep(2)
                return
        except ValueError:
            print(f"{Colors.RED}Invalid number{Colors.RESET}")
            await asyncio.sleep(2)
            return
    
    if brightness is not None:
        if device_type == "floor":
            # White mode format for floor lamps
            brightness_hex = f"{brightness:02X}"
            cmd_str = f"5A000200000000{brightness_hex}00A5"
            cmd = bytes.fromhex(cmd_str)
            await send_command(device, cmd, f"brightness {brightness}", is_color=True)
        else:
            print(f"{Colors.YELLOW}⚠️  Brightness control not yet supported for ceiling lights{Colors.RESET}")
            await asyncio.sleep(2)

async def manage_presets_menu():
    """Manage presets (add/delete)."""
    presets = load_presets()
    
    while True:
        print_header()
        print(f"{Colors.BOLD}Manage Presets{Colors.RESET}\n")
        print(f"  {Colors.YELLOW}1{Colors.RESET}. Add new preset")
        print(f"  {Colors.YELLOW}2{Colors.RESET}. Delete preset")
        print(f"  {Colors.YELLOW}3{Colors.RESET}. Reset to defaults")
        print(f"  {Colors.GRAY}0{Colors.RESET}. Back to main menu\n")
        
        choice = get_input("Choose option: ")
        
        if choice == '0':
            break
        elif choice == '1':
            # Add preset
            print(f"\n{Colors.BOLD}Add New Preset{Colors.RESET}\n")
            name = input(f"Preset name: ").strip()
            if not name:
                continue
            
            try:
                r = int(input(f"{Colors.RED}Red (0-255): {Colors.RESET}").strip())
                g = int(input(f"{Colors.GREEN}Green (0-255): {Colors.RESET}").strip())
                b = int(input(f"{Colors.BLUE}Blue (0-255): {Colors.RESET}").strip())
                
                if all(0 <= x <= 255 for x in (r, g, b)):
                    presets[name] = {"r": r, "g": g, "b": b}
                    save_presets(presets)
                    print(f"{Colors.GREEN}✓ Preset '{name}' added{Colors.RESET}")
                else:
                    print(f"{Colors.RED}Invalid values{Colors.RESET}")
            except ValueError:
                print(f"{Colors.RED}Invalid number{Colors.RESET}")
            
            await asyncio.sleep(1.5)
        
        elif choice == '2':
            # Delete preset
            print_presets(presets)
            try:
                idx = int(get_input("\nDelete preset number (0 to cancel): "))
                if idx > 0:
                    items = list(presets.keys())
                    if 0 < idx <= len(items):
                        name = items[idx - 1]
                        confirm = get_input(f"Delete '{name}'? (y/n): ", ['y', 'n'])
                        if confirm == 'y':
                            del presets[name]
                            save_presets(presets)
                            print(f"{Colors.GREEN}✓ Deleted{Colors.RESET}")
                            await asyncio.sleep(1)
            except ValueError:
                pass
        
        elif choice == '3':
            # Reset to defaults
            confirm = get_input("Reset all presets to defaults? (y/n): ", ['y', 'n'])
            if confirm == 'y':
                save_presets(DEFAULT_PRESETS)
                print(f"{Colors.GREEN}✓ Reset to defaults{Colors.RESET}")
                await asyncio.sleep(1.5)
                break

async def set_device_nickname(device):
    """Set or update device nickname."""
    addr, name, prefix = device
    nicknames = load_devices()
    
    print_header()
    print(f"{Colors.BOLD}Set Device Nickname{Colors.RESET}\n")
    print(f"{Colors.DIM}Device: {name} ({addr}){Colors.RESET}\n")
    
    current = nicknames.get(addr, "")
    if current:
        print(f"Current nickname: {Colors.CYAN}{current}{Colors.RESET}\n")
    
    print("Enter a nickname (or leave empty to remove):")
    nickname = input(f"{Colors.BOLD}> {Colors.RESET}").strip()
    
    if nickname:
        nicknames[addr] = nickname
        save_devices(nicknames)
        print(f"{Colors.GREEN}✓ Nickname set to '{nickname}'{Colors.RESET}")
    elif current:
        del nicknames[addr]
        save_devices(nicknames)
        print(f"{Colors.GREEN}✓ Nickname removed{Colors.RESET}")
    else:
        print(f"{Colors.GRAY}No changes made{Colors.RESET}")
    
    await asyncio.sleep(1.5)

async def main():
    """Main interactive menu loop."""
    print_header()
    print(f"{Colors.BLUE}🔍 Scanning for KS devices...{Colors.RESET}")
    print(f"{Colors.DIM}This may take a few seconds...{Colors.RESET}\n")
    
    devices = await scan_devices(timeout=8.0)
    
    if not devices:
        print(f"{Colors.RED}No KS devices found.{Colors.RESET}")
        print(f"{Colors.DIM}Make sure Bluetooth is enabled and devices are powered on.{Colors.RESET}")
        return
    
    # Device selection
    selected_idx = 0
    nicknames = load_devices()
    while True:
        print_header()
        print_device_list(devices, selected_idx, nicknames)
        
        print(f"{Colors.DIM}Use number to select, Enter to confirm, 'r' to rescan, 'q' to quit{Colors.RESET}")
        choice = get_input("> ").strip().lower()
        
        if choice == 'q':
            return
        elif choice == 'r':
            print(f"\n{Colors.BLUE}🔍 Rescanning...{Colors.RESET}")
            devices = await scan_devices(timeout=8.0)
            if not devices:
                print(f"{Colors.RED}No devices found{Colors.RESET}")
                await asyncio.sleep(2)
                return
            selected_idx = 0
        elif choice == '':
            break
        elif choice.isdigit():
            idx = int(choice) - 1
            if 0 <= idx < len(devices):
                selected_idx = idx
                break  # Confirm selection immediately
    
    device = devices[selected_idx]
    addr, name, prefix = device
    
    # Main menu loop
    presets = load_presets()
    nicknames = load_devices()
    
    while True:
        nicknames = load_devices()  # Reload in case of changes
        display_name = get_device_display_name(addr, name, nicknames)
        print_header()
        print_menu(display_name)
        
        choice = get_input("Choose option: ").strip().lower()
        
        if choice == 'q':
            print(f"\n{Colors.CYAN}Goodbye! 👋{Colors.RESET}\n")
            break
        elif choice == '1':
            cmd = build_on_off_cmd(True)
            await send_command(device, cmd, "ON")
        elif choice == '2':
            cmd = build_on_off_cmd(False)
            await send_command(device, cmd, "OFF")
        elif choice == '3':
            await color_preset_menu(device, presets)
            presets = load_presets()  # Reload in case of changes
        elif choice == '4':
            await custom_color_menu(device)
        elif choice == '5':
            await brightness_menu(device)
        elif choice == '6':
            await manage_presets_menu()
            presets = load_presets()
        elif choice == '7':
            await set_device_nickname(device)
        elif choice == '8':
            # Change device - restart selection
            return await main()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print(f"\n{Colors.CYAN}Goodbye! 👋{Colors.RESET}\n")
