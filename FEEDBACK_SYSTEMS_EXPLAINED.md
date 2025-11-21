
# Proactive Feedback & Passive Learning - Complete Explanation

## Overview

ReFocus uses **two complementary data collection systems** to train the ML model:

1. **Proactive Feedback** - Manual prompts asking users for feedback
2. **Passive Learning** - Automatic inference from user behavior

Both systems work together to create a balanced, comprehensive training dataset.

---

## 🔵 SYSTEM 1: PROACTIVE FEEDBACK

### What It Is

**Proactive Feedback** asks users directly: *"Would a break be helpful now?"* at various usage thresholds. This collects **explicit user opinions** about whether they need intervention.

### How It Works

#### 1. **Trigger Points (When It Asks)**

**A. Overuse Detection Thresholds (Percentage-Based)**
- Triggers when daily OR session usage reaches certain percentages of limits
- Current thresholds: **40%, 50%, 60%, 70%, 80%, 90%, 95%**
- Uses the **higher percentage** (daily vs session)

**Example:**
- Daily limit: 360 min (6 hours)
- Session limit: 120 min (2 hours)
- At 180 min daily (50%) → Triggers feedback
- At 60 min session (50%) → Triggers feedback
- At 216 min daily (60%) → Triggers feedback

**B. Fixed Milestone Levels (Time-Based)**
- Triggers at specific session durations: **20, 40, 60, 90, 120, 150 minutes**
- Independent of daily usage
- Collects feedback at various usage points

#### 2. **Where It Works**

- **Background**: `MonitorService` checks every 1 second (via foreground service)
- **Foreground**: `home_page.dart` checks every 30 seconds when ReFocus is open
- **Any App**: Can show notification from any app (not just ReFocus)

#### 3. **Limits & Safeguards**

- **Daily Limit**: Max **6 prompts per category per day** (prevents spam)
- **Cooldown**: **8 minutes** between prompts (prevents rapid-fire prompts)
- **Minimum Session**: **5 minutes** before first prompt (avoids immediate prompts)
- **Learning Mode Only**: Only works when learning mode is enabled

#### 4. **What Data It Collects**

**User Response:**
- **"Yes, break helpful"** → `wasHelpful = true` (user agrees intervention needed)
- **"No, continue"** → `wasHelpful = false` (user says no intervention needed)

**Data Saved:**
- Category (Social/Games/Entertainment)
- Daily usage (combined for monitored categories)
- Session usage (combined for monitored categories)
- Time of day, day of week
- User's answer (wasHelpful: true/false)
- Prediction source: `'learning_mode'`

#### 5. **Why It's Important**

✅ **Collects "Not Satisfied" Labels**: When user says "No, continue", we learn they were fine at that usage level
✅ **Explicit User Opinion**: Direct feedback, not inferred
✅ **Balanced Dataset**: Gets both "helpful" and "not helpful" responses
✅ **Early Detection**: Can trigger at 40% (before user is overusing)

### Example Scenario

**User at 50% daily limit (180 min):**
1. App shows notification: *"You've used 180 min today. Would a break be helpful?"*
2. User clicks "No, continue" → `wasHelpful = false` logged
3. Model learns: "180 min daily usage = user says no intervention needed"

**User at 80% daily limit (288 min):**
1. App shows notification: *"You've used 288 min today. Would a break be helpful?"*
2. User clicks "Yes, helpful" → `wasHelpful = true` logged
3. Model learns: "288 min daily usage = user says intervention needed"

---

## 🟢 SYSTEM 2: PASSIVE LEARNING

### What It Is

**Passive Learning** automatically infers user satisfaction when they **naturally stop using an app** (without being locked or prompted). It assumes: *"If user stopped naturally, they were satisfied with that usage level."*

### How It Works

#### 1. **Trigger Points (When It Collects Data)**

**A. App Close**
- When user closes an app completely (switches to home screen or another app)
- Tracks: Session duration, daily usage at time of close

**B. App Switch (Between Different Categories)**
- When user switches from one monitored category to another
- Examples:
  - ✅ Social → Games (different categories, triggers)
  - ✅ Games → Entertainment (different categories, triggers)
  - ✅ Entertainment → Social (different categories, triggers)
  - ❌ Social → Social (same category, skipped - considered multitasking)
  - ❌ Games → Games (same category, skipped)

#### 2. **Where It Works**

- **Automatic**: Triggered by `UsageService` when detecting app closes/switches
- **Background**: Works even when ReFocus is closed
- **No User Interaction**: Completely automatic, user doesn't know it's happening

#### 3. **Safeguards (Must Pass All)**

**Safeguard 1: Learning Mode Only**
- Only works when learning mode is enabled
- Doesn't collect data in rule-based mode

**Safeguard 2: Monitored Categories Only**
- Only for Social, Games, Entertainment
- Skips "Others" category

**Safeguard 3: Minimum Session Length**
- Session must be **≥ 10 minutes** (avoids noise from very short sessions)
- Example: 5 min session → Skipped

**Safeguard 4: Maximum Natural Session**
- Session must be **≤ 180 minutes** (3 hours)
- Beyond this might be forced/interrupted, not natural
- Example: 200 min session → Skipped

**Safeguard 5: Not Forced Close**
- User must not reopen app within **5 minutes**
- If reopened quickly, it's likely a forced close, not natural stop
- Example: Close app, reopen 2 min later → Skipped

**Safeguard 6: No Duplicates**
- Same app close within **30 minutes** → Skipped
- Prevents duplicate inference from same behavior

**Safeguard 7: Not Near Limits**
- Usage must be **< 95%** of limits
- If near limit, might have been forced by limit, not natural
- Example: 95% daily usage → Skipped

#### 4. **What Data It Collects**

**Inferred Label:**
- **Always `wasHelpful = true`** (natural stop = satisfied = no lock needed)

**Data Saved:**
- Category (Social/Games/Entertainment)
- Daily usage (combined for monitored categories)
- Session usage (combined for monitored categories)
- Time of day, day of week
- Inferred label: `wasHelpful = true`
- Prediction source: `'passive_learning'`

#### 5. **Why It's Important**

✅ **Collects "Satisfied" Labels**: When user naturally stops, we learn they were satisfied
✅ **No User Burden**: Completely automatic, no prompts
✅ **High Volume**: Can collect 10-20 samples/day per user
✅ **Real Behavior**: Based on actual user actions, not opinions

### Example Scenario

**User uses Instagram (Social) for 45 minutes, then closes app:**
1. `UsageService` detects app close
2. Calls `PassiveLearningService.onAppClosed()`
3. Checks safeguards:
   - ✅ Learning mode: Yes
   - ✅ Category: Social (monitored)
   - ✅ Session: 45 min (10-180 min range)
   - ✅ Not near limit: 45 min < 95% of 120 min limit
   - ✅ Not forced: User didn't reopen quickly
4. All safeguards pass → Logs feedback:
   - `wasHelpful = true` (natural stop = satisfied)
   - `sessionUsageMinutes = 45`
   - `dailyUsageMinutes = 180` (combined Social+Games+Entertainment)
   - `predictionSource = 'passive_learning'`

**User switches from Instagram (Social) to Candy Crush (Games):**
1. `UsageService` detects app switch
2. Calls `PassiveLearningService.onAppSwitch()`
3. Checks: Different categories? ✅ Yes (Social → Games)
4. Calls `onAppClosed()` with same safeguards
5. If passes → Logs feedback (same as above)

---

## 🔄 HOW THEY WORK TOGETHER

### Complementary Roles

| Aspect | Proactive Feedback | Passive Learning |
|-------|-------------------|------------------|
| **Data Type** | Explicit user opinion | Inferred from behavior |
| **Labels** | Both `true` and `false` | Only `true` (satisfied) |
| **User Interaction** | Requires user response | Completely automatic |
| **Volume** | 4-6 samples/day | 10-20 samples/day |
| **When** | At thresholds (40%, 50%, etc.) | When user naturally stops |
| **Purpose** | Learn when to intervene | Learn when NOT to intervene |

### Data Collection Flow

```
User Behavior:
├── Natural App Close
│   └── Passive Learning → wasHelpful = true (satisfied)
│
├── Reaches 50% Threshold
│   └── Proactive Feedback → User says "No, continue" → wasHelpful = false
│
├── Reaches 80% Threshold
│   └── Proactive Feedback → User says "Yes, helpful" → wasHelpful = true
│
└── Natural App Switch (Social → Games)
    └── Passive Learning → wasHelpful = true (satisfied)
```

### Balanced Dataset Creation

**Without Proactive Feedback:**
- Only "satisfied" labels (wasHelpful = true)
- Model learns: "Never lock" (biased)

**With Both Systems:**
- "Satisfied" labels (passive learning)
- "Not satisfied" labels (proactive feedback - "No, continue")
- "Intervention needed" labels (proactive feedback - "Yes, helpful")
- Model learns: "When to lock AND when NOT to lock" (balanced)

---

## 📊 EXPECTED DATA COLLECTION

### Per User Per Day

**Proactive Feedback (Manual):**
- Heavy user (6 hours): ~4-6 prompts/day
- Moderate user (3 hours): ~3-4 prompts/day
- Light user (1 hour): ~1-2 prompts/day

**Passive Learning (Automatic):**
- Typical user: ~10-20 samples/day
- Based on natural app closes/switches

**Total:**
- ~14-26 samples/day per user
- Mix of "satisfied" and "not satisfied" labels

---

## ⚙️ CONFIGURATION (Option 2 - Aggressive)

### Proactive Feedback Settings

```dart
// Fixed milestone levels (minutes)
PROMPT_LEVELS = [20, 40, 60, 90, 120, 150]

// Overuse thresholds (percentage of limit)
OVERUSE_THRESHOLDS = [0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 0.95]

// Daily limit per category
MAX_PROMPTS_PER_CATEGORY_PER_DAY = 6

// Cooldown between prompts (minutes)
PROMPT_COOLDOWN_MINUTES = 8

// Minimum session before prompting (minutes)
MIN_SESSION_ACTIVITY_MINUTES = 5
```

### Passive Learning Settings

```dart
// Minimum session for inference (minutes)
MIN_SESSION_MINUTES_FOR_INFERENCE = 10

// Maximum natural session (minutes)
MAX_NATURAL_SESSION_MINUTES = 180

// Minimum stop duration (minutes)
MIN_STOP_DURATION_MINUTES = 5

// Duplicate prevention window (minutes)
DUPLICATE_PREVENTION_WINDOW = 30

// Near-limit threshold (percentage)
NEAR_LIMIT_THRESHOLD = 0.95
```

---

## 🎯 KEY TAKEAWAYS

1. **Proactive Feedback** = Explicit user opinions (both "helpful" and "not helpful")
2. **Passive Learning** = Inferred satisfaction (only "satisfied" labels)
3. **Both are needed** for balanced ML training
4. **Proactive Feedback** collects "not satisfied" labels (critical for learning when NOT to lock)
5. **Passive Learning** collects "satisfied" labels automatically (high volume, no user burden)
6. **Together** they create a comprehensive, balanced training dataset

---

## 📝 SUMMARY

**Proactive Feedback:**
- Asks users directly for feedback
- Collects both "helpful" and "not helpful" responses
- Triggers at usage thresholds (40%, 50%, 60%, etc.)
- 4-6 prompts/day (with Option 2)

**Passive Learning:**
- Automatically infers satisfaction from natural stops
- Collects only "satisfied" labels
- Triggers on app closes/switches
- 10-20 samples/day (automatic)

**Result:**
- Balanced dataset with both positive and negative labels
- Comprehensive coverage of usage scenarios
- Faster ML model training and better accuracy

