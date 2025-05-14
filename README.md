# LagGuard

## A World of Warcraft Classic Hardcore Addon

LagGuard is a specialized addon designed to protect hardcore players from deaths due to unexpected lag spikes. By continuously monitoring your connection to the game servers, LagGuard provides timely warnings when your latency reaches dangerous levels, giving you a chance to react before it's too late.

## Features

### Core Functionality
- **Real-time Latency Monitoring**: Constantly tracks both home and world server latency
- **Smart Baseline Detection**: Establishes your normal baseline connection quality and detects deviations
- **Multi-level Warning System**: Provides escalating alerts based on severity
- **Customizable Thresholds**: Set your own latency thresholds for warnings
- **Visual Status Indicator**: Shows your current connection status at a glance
- **Multiple Alert Types**: Configurable text, sound, and screen flash warnings

### Combat Safety Features
- **Combat Entry Warnings**: Alerts when entering combat with high latency
- **Class-specific Defensive Cooldowns**: Suggests available defensive abilities during lag spikes
- **Party/Raid Notifications**: Optionally notify group members when experiencing severe lag
- **Auto-protection Measures**: Options to automatically cancel spellcasting or follow during severe lag

### Advanced Analytics
- **Latency Trend Analysis**: Detects patterns in your connection quality
- **Time-of-Day Tracking**: Identifies which hours typically have better or worse latency
- **Connection Quality Scoring**: Provides a comprehensive score for your overall connection health
- **Predictive Warnings**: Forecasts potential latency issues before they become severe
- **Jitter & Packet Loss Detection**: Monitors advanced network metrics beyond simple latency

### Map & Zone Features
- **Zone Latency Heat Map**: Shows which areas have historically better or worse connections
- **Safe Zone Detection**: Identifies zones with consistently stable connections
- **Zone Ranking System**: Compares latency quality across all visited zones
- **Travel Recommendations**: Suggests avoiding high-lag zones for critical activities

### Enhanced UI
- **Minimap Button**: Quick access to all LagGuard features with status indicator
- **Latency Log**: Detailed record of latency events with timestamps and severity
- **Exportable Data**: Share or analyze your connection history
- **Compact Mode**: Minimal UI option for distraction-free play
- **Time-based Graphs**: Visual representation of latency patterns

## Usage

After installation, LagGuard will automatically begin monitoring your connection. You'll see a small indicator in the top-right corner of your screen showing your current connection status:

- **Green**: Connection is good
- **Orange**: Caution - Minor latency issues detected
- **Yellow**: Warning - Significant latency detected
- **Red**: Danger - Severe latency issues detected

When latency spikes occur, you'll receive alerts based on your settings, which may include:
- On-screen text warnings
- Sound alerts
- Screen flashes (for severe warnings)
- Chat messages
- Defensive ability suggestions
- Group notifications

## Commands

### Basic Commands
- **/lg** or **/lagguard** - Shows help message with available commands
- **/lg toggle** - Toggles the addon on/off
- **/lg config** - Opens the configuration panel

### Visual Tools
- **/lg graph** - Display the latency trend graph
- **/lg score** - Show/hide connection quality score
- **/lg map** - Show zone latency map
- **/lg time** - Show time of day analysis

### Data Tools
- **/lg log** - Show latency event log
- **/lg safezone** - Check if your current zone has stable latency
- **/lg analytics** - Show current analytics stats
- **/lg minimap** - Toggle minimap button

## Configuration

LagGuard offers extensive customization through its configuration panel:

1. **Alert Types**: Choose which alert methods to enable (sound, text, screen flash)
2. **Thresholds**: Set the latency levels that trigger different warning levels
3. **Monitoring Options**: Configure which latency types to monitor (home/world)
4. **Baseline Settings**: Adjust how your normal latency baseline is calculated
5. **Combat Safety**: Configure defensive recommendations and group notifications
6. **UI Options**: Minimap button, compact mode, and display preferences
7. **Analytics**: Customize trend analysis and predictive warnings
8. **Logging Options**: Adjust log size and entry criteria

## For Hardcore Players

In the unforgiving world of hardcore mode, a single death means the end of your character. Network lag is one of the few factors outside of your control that can lead to an unfair death. LagGuard helps mitigate this risk by:

1. Warning you to stop engaging in combat when lag is detected
2. Suggesting appropriate defensive cooldowns for your class during lag spikes
3. Identifying times of day and zones with higher lag risk
4. Providing predictive warnings before latency becomes critical
5. Giving you comprehensive tools to understand and manage your connection quality

## Installation

1. Download the latest version from [CurseForge](https://www.curseforge.com/wow/addons/lagguard) or [WoWInterface](https://www.wowinterface.com/downloads/info-LagGuard.html)
2. Extract the folder into your World of Warcraft\_classic_\\Interface\\AddOns directory
3. Restart World of Warcraft if it's currently running
4. Ensure the addon is enabled in your addon list

## Version History

### Version 1.1.0
- Added minimap button with latency status indicator
- Added combat safety features with defensive cooldown suggestions
- Added zone latency map and zone quality tracking
- Added time-of-day analytics and prediction system
- Improved latency log with timestamps and export capability
- Added connection quality scoring system
- Many UI improvements and bug fixes

### Version 1.0.0
- Initial release with core latency monitoring features

## Help & Support

If you encounter any issues or have suggestions for improvement:

- Leave a comment on the [CurseForge page](https://www.curseforge.com/wow/addons/lagguard)

## License

LagGuard is released under the MIT License. See the LICENSE file for more details.

---

Created with ❤️ for the hardcore community 
