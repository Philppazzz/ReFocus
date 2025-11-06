# Emergency Override System

## Overview
The Emergency Override system provides users with a once-per-day emergency escape from all app restrictions. It's designed to be used in genuine emergencies while preventing abuse through daily limits.

## Key Features

### 1. Once-Per-Day Limit
- Emergency override can only be activated **once per day**
- Resets at midnight automatically
- Shows countdown in hours until next availability if already used

### 2. Synchronized State
- Emergency state is synced between:
  - Home page drawer toggle
  - Lock screen emergency button
  - Background monitoring service
  - Usage tracking service
- Uses both `SharedPreferences` and `AppState` singleton for reliability

### 3. Confirmation Dialog
Both activation points (drawer and lock screen) show a clear confirmation dialog with:
- Warning icon and title
- List of what will happen
- Prominent "once per day" warning
- Cancel and Confirm buttons

### 4. What Emergency Override Does

#### When Activated:
✅ **Stops ALL tracking** - No usage, session, or unlock counting
✅ **Clears all locks** - Removes daily lock, session cooldown, unlock cooldown
✅ **Resets session timer** - Session starts fresh from 0
✅ **Resets unlock counter** - Unlock count starts fresh from 0
✅ **Preserves daily usage** - Daily usage total is maintained
✅ **Closes lock screen** - If activated from lock screen, it closes immediately
✅ **Logs to database** - Records emergency activation for analytics

#### When Deactivated:
✅ **Resumes tracking** - All monitoring restarts
✅ **Skips emergency period** - Events during emergency are not counted
✅ **Daily limit still applies** - If daily limit was reached, it remains locked

### 5. Important Behaviors

#### Daily Usage Special Case:
- Session and unlock limits are reset by emergency
- **Daily usage limit is NOT reset** - it persists until midnight
- If user had reached daily limit before emergency, they'll be locked again when they turn it off

#### Tracking During Emergency:
- **No tracking occurs** while emergency is ON
- Usage stats are frozen at the moment emergency was activated
- When turned OFF, tracking resumes from that moment
- Events that occurred during emergency period are skipped

#### Lock Screen Interaction:
- If user is locked and activates emergency from lock screen:
  - Lock screen closes immediately
  - User can access all apps
  - Session/unlock counters reset
  - Daily usage preserved

## Implementation Details

### Files Modified

#### 1. `lib/services/emergency_service.dart` (NEW)
Comprehensive emergency service with:
- `hasUsedEmergencyToday()` - Check if already used
- `activateEmergency()` - Activate with full state management
- `deactivateEmergency()` - Deactivate and resume tracking
- `isEmergencyActive()` - Check current state
- `getHoursUntilAvailable()` - Time until next availability
- `resetEmergencyUsage()` - Testing utility

#### 2. `lib/pages/home_page.dart`
- Added import for `EmergencyService`
- Updated `_toggleOverride()` to use new service with confirmation
- Added `_syncEmergencyState()` in both HomePage and AppDrawer
- Emergency button in drawer now shows confirmation dialog
- Syncs state on app startup

#### 3. `lib/pages/lock_screen.dart`
- Added import for `EmergencyService`
- Updated `_showEmergencyUnlockDialog()` to use new service
- Shows same confirmation dialog as drawer
- Checks if already used today before showing dialog
- Closes lock screen after successful activation

#### 4. `lib/services/usage_service.dart`
- Already checks `emergency_override_enabled` in SharedPreferences
- Returns cached stats when emergency is ON
- Skips events during emergency period

#### 5. `lib/services/monitor_service.dart`
- Already checks `AppState().isOverrideEnabled`
- Pauses all monitoring when emergency is ON
- No violations enforced during emergency

### SharedPreferences Keys

```dart
'emergency_used_today'           // bool - Has emergency been used today?
'emergency_date'                 // String - Date of last emergency use
'emergency_override_enabled'     // bool - Is emergency currently active?
'emergency_override_start_time'  // int - Timestamp when emergency started
'cached_daily_usage_$today'      // double - Daily usage preserved during emergency
```

### State Flow

```
User taps Emergency Override
         ↓
Check if already used today
         ↓
    [If YES] → Show "Available in X hours" message
         ↓
    [If NO] → Show confirmation dialog
         ↓
User confirms
         ↓
EmergencyService.activateEmergency()
         ↓
- Mark as used today
- Set emergency_override_enabled = true
- Clear all locks and cooldowns
- Reset session timer
- Reset unlock counter
- Preserve daily usage
- Update last_check timestamp
- Log to database
         ↓
AppState.isOverrideEnabled = true
         ↓
MonitorService checks and pauses
UsageService checks and returns cached stats
         ↓
User can use all apps freely
         ↓
User turns OFF emergency
         ↓
EmergencyService.deactivateEmergency()
         ↓
- Set emergency_override_enabled = false
- Update last_check to NOW
- Clear stats cache
- Restart monitoring
         ↓
AppState.isOverrideEnabled = false
         ↓
Normal tracking resumes
```

## User Experience

### From Home Drawer:
1. User opens drawer
2. Sees "Emergency Override: OFF" button
3. Taps button
4. Sees confirmation dialog with details
5. Taps "Confirm"
6. Button changes to "Emergency Override: ON" (pulsing red)
7. All tracking stops, locks cleared
8. User can tap again to turn OFF

### From Lock Screen:
1. User is locked (any violation type)
2. Long-presses emergency button (1 second)
3. Sees same confirmation dialog
4. Taps "Confirm"
5. Lock screen closes immediately
6. All apps accessible
7. Session/unlock counters reset
8. Can turn OFF from drawer later

### Already Used Today:
1. User tries to activate emergency
2. Sees message: "Emergency override already used today. Available in 8 hours."
3. Cannot activate until tomorrow

## Testing

### Test Cases:

1. **First Use of Day**
   - Activate emergency → Should work
   - Try again → Should show "already used" message

2. **From Lock Screen**
   - Get locked (any violation)
   - Long-press emergency
   - Confirm → Lock screen should close

3. **Session Reset**
   - Build up session time
   - Activate emergency
   - Deactivate emergency
   - Session should start from 0

4. **Unlock Reset**
   - Open apps multiple times
   - Activate emergency
   - Deactivate emergency
   - Unlock count should start from 0

5. **Daily Usage Preserved**
   - Build up daily usage
   - Activate emergency
   - Check stats → Daily usage should be same
   - Deactivate → Daily usage continues from where it was

6. **Tracking Stopped**
   - Activate emergency
   - Use apps heavily
   - Check stats → Should not increase
   - Deactivate → Stats resume from before emergency

7. **Sync Between Drawer and Lock Screen**
   - Activate from drawer
   - Get locked somehow
   - Emergency button should show "already used"

## Security Considerations

### Abuse Prevention:
- ✅ Once-per-day limit prevents constant abuse
- ✅ Logged to database for analytics
- ✅ Clear warning that it's limited
- ✅ No way to bypass the daily limit (except testing function)

### Data Integrity:
- ✅ Daily usage preserved (can't cheat daily limit)
- ✅ Events during emergency are skipped (no retroactive counting)
- ✅ State synced across multiple sources
- ✅ Proper cleanup on deactivation

## Future Enhancements (Optional)

1. **Biometric Confirmation**
   - Require fingerprint/face ID to activate
   - Extra layer of security

2. **Emergency Reason**
   - Optional text field for user to explain why
   - Helps with self-reflection

3. **Emergency Statistics**
   - Show how many times used this week/month
   - Trend analysis

4. **Graduated Cooldown**
   - First emergency: 24 hour cooldown
   - Second emergency: 48 hour cooldown
   - Encourages less frequent use

5. **Emergency Contacts Notification**
   - Optionally notify trusted contact when emergency used
   - Accountability feature

## Notes

- Emergency override is a **safety valve**, not a regular feature
- It's designed for genuine emergencies (urgent call, important message, etc.)
- The once-per-day limit encourages users to plan their usage better
- Daily usage limit remains enforced to maintain the core goal of reducing screen time

