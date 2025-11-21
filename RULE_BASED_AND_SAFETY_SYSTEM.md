# Rule-Based & Safety Limits System

## ✅ **Complete System Overview**

The app now has a **two-tier protection system** that balances user preferences with universal safety:

### **1. Safety Limits (Universal Maximum)**
- **Daily**: 360 minutes (6 hours) - **ALWAYS enforced**
- **Session**: 120 minutes (2 hours) - **ALWAYS enforced**
- **Purpose**: Universal protection for all users (no bias, maximum safety)
- **Enforcement**: Applied in `HybridLockManager` before any other checks
- **Cannot be exceeded**: Even if user customizes rule-based limits

### **2. Rule-Based Limits (User Preference)**
- **Default Daily**: 180 minutes (3 hours) - **Stricter than safety**
- **Default Session**: 60 minutes (1 hour) - **Stricter than safety**
- **Purpose**: For users who want immediate locking or prefer stricter control
- **Customizable**: Users can set their own limits (e.g., 1 hour session)
- **Validation**: Cannot exceed safety limits (automatically clamped)

---

## 🔄 **How It Works**

### **For Users Who Want Immediate Locking:**
1. **Rule-based mode enabled** → Uses stricter defaults (3h/1h)
2. **User can customize** → Set even stricter limits (e.g., 1h session)
3. **Safety limits still protect** → If user exceeds 6h/2h, safety kicks in
4. **ML learns preferences** → Model adapts to user's rule-based choices

### **For Users in Learning Mode:**
1. **No locks** (except safety limits) → Collects unbiased data
2. **Adapts to user patterns** → `AdaptiveThresholdManager` adjusts limits
3. **Safety limits prevent abuse** → Cannot exceed 6h/2h even in learning mode
4. **ML training** → Uses collected feedback to learn user preferences

### **For Users with ML Active:**
1. **ML learns from feedback** → Adapts to user's preferred limits
2. **Quality-adjusted weights** → Balances rule-based and ML predictions
3. **Safety limits always enforced** → Universal maximum protection
4. **Ensemble decision** → Combines rule-based + ML with confidence

### **For Users Decreasing Screen Time:**
1. **AdaptiveThresholdManager monitors** → Tracks usage patterns (7-day window)
2. **Reduces limits when improving** → If usage < 70% and satisfaction > 75%
3. **Helps maintain progress** → Sets limit slightly above average (10% buffer)
4. **Cannot go below minimums** → Clamped to safe minimums (4h/1.5h)

---

## 📊 **Adaptive System Details**

### **AdaptiveThresholdManager**
- **Evaluation Window**: Last 7 days
- **Reduction Trigger**: Usage < 70% of limit AND satisfaction > 75%
- **Increase Trigger**: Usage > 95% of limit AND satisfaction < 50%
- **Minimum Limits**: 240 min daily, 90 min session (cannot go below)
- **Maximum Limits**: 480 min daily, 150 min session (cannot exceed)
- **Adjustment Frequency**: Once per 7 days (prevents daily changes)

### **ML Adaptation**
- **Quality-Adjusted Weights**:
  - High helpfulness (>70%) → Balanced (50/50 rule-based/ML)
  - Medium helpfulness (40-70%) → Rule-based favored (70/30)
  - Low helpfulness (<40%) → Rule-based heavily favored (90/10)
- **Feedback Learning**: ML learns from user's rule-based preferences
- **Personalization**: Model adapts to user's actual behavior patterns

---

## 🛡️ **Safety & Validation**

### **Validation in AppLockManager**
```dart
// Rule-based limits are automatically validated
// Cannot exceed safety limits (360/120)
final validated = await _validateThresholds(category, dailyLimit, sessionLimit);
```

### **Safety Enforcement in HybridLockManager**
```dart
// Step 1: ALWAYS enforce safety limits FIRST
if (_exceedsSafetyLimits(combinedDailyMinutes, combinedSessionMinutes)) {
  return {'shouldLock': true, 'source': 'safety_override', ...};
}
```

### **Learning Mode Safety**
- Learning mode respects safety limits
- No locks below safety limits (collects data)
- Safety limits enforced even in learning mode

---

## ✅ **Current System Status**

| Feature | Status | Details |
|---------|--------|---------|
| **Safety Limits** | ✅ Active | 360/120 min (universal maximum) |
| **Rule-Based Defaults** | ✅ Updated | 180/60 min (stricter, user preference) |
| **Validation** | ✅ Active | Rule-based cannot exceed safety |
| **Learning Mode** | ✅ Active | Adapts to user, respects safety |
| **ML Adaptation** | ✅ Active | Learns from user preferences |
| **Adaptive Thresholds** | ✅ Active | Reduces limits when user improves |
| **User Customization** | ✅ Active | Users can set stricter limits |

---

## 🎯 **Benefits**

### **For Users Who Want Immediate Control:**
- ✅ Stricter defaults (3h/1h) for immediate locking
- ✅ Can customize to be even stricter (e.g., 1h session)
- ✅ Safety limits still protect (6h/2h maximum)

### **For Users in Learning Mode:**
- ✅ No locks (except safety) - collects unbiased data
- ✅ Adapts to user patterns automatically
- ✅ Safety limits prevent abuse

### **For Users with ML Active:**
- ✅ ML learns from user's rule-based preferences
- ✅ Adapts to user's preferred limits
- ✅ Safety limits always enforced

### **For Users Decreasing Screen Time:**
- ✅ AdaptiveThresholdManager reduces limits when improving
- ✅ Helps maintain progress
- ✅ Cannot go below minimum thresholds

---

## 📝 **Implementation Details**

### **Files Modified:**
1. **`lib/services/app_lock_manager.dart`**:
   - Updated defaults to 180/60 (stricter)
   - Added `_validateThresholds()` method
   - Updated `_getThresholds()` to validate
   - Updated `updateThreshold()` to validate

### **Files Already Supporting:**
1. **`lib/services/hybrid_lock_manager.dart`**:
   - Enforces safety limits first
   - Uses rule-based for immediate control
   - ML adapts to user preferences

2. **`lib/services/adaptive_threshold_manager.dart`**:
   - Reduces limits when user improves
   - Increases limits when user struggles
   - Respects min/max thresholds

3. **`lib/services/ensemble_model_service.dart`**:
   - Quality-adjusted weights
   - Adapts to user feedback patterns
   - Balances rule-based and ML

---

## 🔍 **Verification**

### **To Verify Rule-Based Defaults:**
1. Check `AppLockManager.getThresholds('Social')` → Should return 180/60
2. Check `AppLockManager.getThresholds('Games')` → Should return 180/60
3. Check `AppLockManager.getThresholds('Entertainment')` → Should return 180/60

### **To Verify Safety Limits:**
1. Check `HybridLockManager.shouldLockApp()` with 400 min daily → Should lock (safety)
2. Check `HybridLockManager.shouldLockApp()` with 150 min session → Should lock (safety)

### **To Verify Validation:**
1. Try `AppLockManager.updateThreshold(category: 'Social', dailyLimit: 400)` → Should clamp to 360
2. Try `AppLockManager.updateThreshold(category: 'Social', sessionLimit: 150)` → Should clamp to 120

### **To Verify Adaptive System:**
1. Use app for 7+ days with usage < 70% of limit
2. Provide helpful feedback (>75% satisfaction)
3. Check `AdaptiveThresholdManager.evaluateAndAdjust()` → Should reduce limits

---

## ✅ **Summary**

The system now provides:
- **Universal Protection**: Safety limits (6h/2h) - always enforced
- **User Flexibility**: Rule-based (3h/1h default, customizable) - for immediate control
- **Immediate Control**: Stricter defaults for users who want locking right away
- **Adaptive Learning**: ML + adaptive thresholds adapt to user preferences
- **Progress Support**: Reduces limits when user improves screen time

**All systems are working together to provide the best user experience while maintaining safety!** 🎉

