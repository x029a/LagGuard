# LagGuard Addon - Complete Changelog

## Initial Fixes:

### 1. Enable/Disable Functionality
- Fixed the enable/disable toggle in `Config.lua` to properly update the UI.
- Added immediate UI refresh when toggling the addon on/off.
- Implemented a delay mechanism when re-enabling to ensure proper UI recreation.
- Ensured synchronization between main config panel and interface options panel toggles.

### 2. Position Saving for Latency Displays
- Added proper position saving and loading for display frames.
- Added `PLAYER_LOGIN` event handler to ensure positions are loaded after relogging.
- Fixed frame initialization to properly restore saved positions.

### 3. Graph Display and Positioning
- Repositioned the graph button to prevent overlapping with other UI elements.
- Improved graph layout in compact mode to avoid UI conflicts.

### 4. UpdateAlertFrameLayout Function Fix
- Fixed timing issue where `UpdateAlertFrameLayout` was called before being defined.
- Added defensive checks to ensure the function exists before calling it.
- Implemented a delayed call to handle layout updates in the correct order.

### 5. Latency Log Improvements
- Modified `LogLatencyEvent` to avoid duplicate entries and ensure proper recording.
- Added timestamp with date and time information to log entries.
- Increased timestamp column width to properly display dates.
- Added duplicate detection to prevent log spam.
- Added automatic updates for the log UI when new entries are added.

### 6. Frequent Latency Status Updates
- Reduced the interval for periodic status updates from 60 to 30 seconds.
- Added additional diagnostic information for severe latency spikes.
- Enhanced log entries with connection quality score information.
- Added initialization entries when the log is first opened.

### 7. UI Visibility State Management
- Fixed `alertFrame` visibility to properly match the addon's enabled state.
- Added final verification of enabled state at the end of initialization.
- Improved the display update mechanism to properly handle state changes.

### 8. Additional UI Enhancements
- Improved log UI with column headers and a divider line.
- Added an export function for the latency log.
- Added a "No entries" message when the log is empty.
- Enhanced frame creation with proper error handling.

## New Major Features:

### 9. Minimap Button
- Added a draggable minimap button for quick access to LagGuard features.
- Implemented color-coded status indicator based on current latency.
- Created dropdown menu with access to all major features.
- Added toggle option in both main config panel and interface options.

### 10. Combat Safety Features
- Added automatic combat entry warnings during high latency periods.
- Implemented class-specific defensive cooldown suggestions.
- Added party/raid notifications during severe lag.
- Created detailed combat latency monitoring system.
- Added automatic tracking of combat state for timely warnings.

### 11. Zone Latency Map
- Created zone-based latency tracking and visualization.
- Added ranking system for zones by latency quality.
- Implemented color-coded zone status indicators.
- Added detailed tooltips with zone-specific latency information.
- Included historical tracking to identify consistently problematic areas.

### 12. Advanced Time-Based Analytics
- Added time-of-day latency tracking and visualization.
- Created bar chart visualization of hourly latency patterns.
- Implemented latency forecasting for upcoming hours.
- Added predictive warnings for high-latency time periods.
- Created interactive tooltips with detailed hour-by-hour statistics.

### 13. Expanded UI and Configuration Options
- Added UI options to enable/disable new features.
- Updated help text and command list to include all new features.
- Enhanced slash command system for accessing all features.
- Improved color coding and status indicators throughout.
- Added minimap button toggle options in settings panels.