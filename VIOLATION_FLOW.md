# 🔒 Violation & Reset Flow - ReFocus App

## 📊 How Violations Work

### Violation Types & Priority Order

1. **Daily Usage Limit** (HIGHEST PRIORITY) 🔴
   - Limit: 1.2 minutes (72 seconds) currently for testing
   - **When reached**: LOCKS ALL APPS UNTIL TOMORROW
   - **Reset**: Midnight only
   - **Overrides**: ALL other limits (session/unlock)

2. **Max Session Limit** (MEDIUM PRIORITY) 🟠
   - Limit: 5 minutes (300 seconds) currently for testing
   - **When reached**: Cooldown with increasing punishment
   - **Reset**: After cooldown expires
   - **Progressive Punishment**: 5s → 10s → 15s → 20s → 30s → 60s

3. **Most Unlock Limit** (LOWEST PRIORITY) 🟡
   - Limit: 3 unlocks currently for testing
   - **When reached**: Cooldown with increasing punishment
   - **Reset**: After cooldown expires
   - **Progressive Punishment**: 5s → 10s → 15s → 20s → 30s → 60s

---

## 🔄 Normal Violation Flow (Session/Unlock)

### Example: Max Session Limit

**1st Violation:**
```
User uses app for 5 minutes continuously
↓
🚨 Session limit reached!
↓
System:
  - Records violation (#1)
  - Resets session timer to 0
  - Applies 5-second cooldown
  - Shows lock screen
↓
User waits 5 seconds
↓
✅ Lock screen dismissed
↓
Session counter reset to 0
Unlock counter reset to current count
User can use apps normally again
```

**2nd Violation (Same Day):**
```
User violates session limit AGAIN
↓
🚨 Session limit reached!
↓
System:
  - Records violation (#2)
  - Resets session timer to 0
  - Applies 10-second cooldown (INCREASED!)
  - Shows lock screen
↓
User waits 10 seconds
↓
✅ Lock screen dismissed
↓
Fresh start with reset counters
```

**3rd, 4th, 5th, 6th+ Violations:**
- Cooldown keeps increasing: 15s → 20s → 30s → 60s (max)
- Each time, counters reset after cooldown
- User gets fresh start but with longer punishment

---

## 🛑 Daily Limit Flow (ABSOLUTE LOCK)

### When Daily Limit is Reached

**Scenario:**
```
User accumulates 72 seconds of usage (1.2 minutes)
↓
🚨 DAILY LIMIT REACHED!
↓
System:
  - Clears any existing session/unlock cooldowns
  - Sets 'daily_locked' = true
  - Shows lock screen with "Unlocks Tomorrow"
  - NO TIMER - just "🌅 Next Day"
↓
User CANNOT use any selected apps
- Session violations ignored (doesn't matter anymore)
- Unlock violations ignored (doesn't matter anymore)
- ONLY emergency unlock or midnight can unlock
↓
⏰ Midnight arrives
↓
System automatically:
  - Clears 'daily_locked'
  - Resets all violation counts to 0
  - Resets all counters
  - Fresh start for new day!
```

---

## ✅ How Resets Work

### After Session/Unlock Cooldown Expires:

```dart
// What gets reset:
1. ✅ Session timer → 0 (fresh 5-minute session)
2. ✅ Unlock base → current count (fresh 3 unlocks)
3. ✅ Cooldown cleared
4. ❌ Violation count → PERSISTS (for increasing punishment)
```

### After Daily Midnight Reset:

```dart
// What gets reset:
1. ✅ Daily usage → 0
2. ✅ Session timer → 0
3. ✅ Unlock base → 0
4. ✅ Violation counts → 0 (back to 5-second punishment)
5. ✅ Daily lock → cleared
6. ✅ All cooldowns → cleared
```

---

## 🧪 Testing Scenarios

### Test 1: Session Violations with Increasing Punishment

1. Use Facebook for 5 minutes → **LOCKED for 5 seconds**
2. Wait 5 seconds → Unlocked
3. Use Facebook for 5 minutes again → **LOCKED for 10 seconds** ✅
4. Wait 10 seconds → Unlocked
5. Use Facebook for 5 minutes again → **LOCKED for 15 seconds** ✅
6. Continue... → 20s, 30s, 60s (max)

**Expected**: Each violation increases the punishment timer.

### Test 2: Unlock Violations with Increasing Punishment

1. Open Facebook 3 times → **LOCKED for 5 seconds**
2. Wait 5 seconds → Unlocked
3. Open Facebook 3 times again → **LOCKED for 10 seconds** ✅
4. Wait 10 seconds → Unlocked
5. Open Facebook 3 times again → **LOCKED for 15 seconds** ✅
6. Continue... → 20s, 30s, 60s (max)

**Expected**: Each violation increases the punishment timer.

### Test 3: Daily Limit Overrides Everything

1. Violate session limit → **LOCKED for 5 seconds**
2. Wait 5 seconds → Unlocked
3. Continue using until 72 seconds total → **DAILY LIMIT REACHED!** 🔴
4. Lock screen shows "Unlocks Tomorrow" with NO timer
5. **Cannot use apps** - session/unlock violations are ignored
6. Wait until midnight → Everything resets ✅

**Expected**: Daily limit completely locks all apps until tomorrow, regardless of session/unlock status.

### Test 4: Reset After Cooldown Works Correctly

1. Violate session limit (5 minutes) → **LOCKED for 5 seconds**
2. Wait 5 seconds → Unlocked
3. Session timer is now at 0 (RESET) ✅
4. Use app for another 5 minutes → **LOCKED for 10 seconds** (increased) ✅
5. Counters reset properly each time ✅

**Expected**: After each cooldown, counters reset but violations persist (for increasing punishment).

---

## 🎯 Summary

### Normal Behavior:
- ✅ Session/Unlock violations → Cooldown → Reset → Can use apps again
- ✅ Punishment increases with each violation (5s, 10s, 15s, 20s, 30s, 60s)
- ✅ Counters reset after cooldown (fresh start)
- ✅ Violations persist (for progressive punishment)

### Daily Limit Behavior:
- 🛑 Daily limit reached → ABSOLUTE LOCK until tomorrow
- 🛑 Overrides all other limits
- 🛑 No timer (just "Next Day")
- 🛑 Only emergency unlock or midnight can unlock

### Midnight Reset:
- 🌅 Everything resets at midnight
- 🌅 Fresh start for new day
- 🌅 Punishment timers back to 5 seconds

