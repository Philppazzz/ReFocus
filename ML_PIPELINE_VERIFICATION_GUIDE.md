# 🧪 ML Pipeline Verification Guide

## ✅ Quick Verification Checklist

Use this guide to verify the ML pipeline works end-to-end in the real app.

---

## 📱 **Step 1: Check ML Status on Home Page**

1. Open the ReFocus app
2. Look at the **ML Status Widget** at the top of the home page
3. Verify status:
   - **"Collecting Data"** (Gray) = Not enough feedback yet (< 300 samples)
   - **"Ready to Train"** (Blue) = 300+ samples, ready for training
   - **"ML Trained"** (Orange) = Model trained, waiting for activation
   - **"ML Active"** (Green) = ✅ ML is working! Using ML + Rule-based

---

## 🔒 **Step 2: Verify ML Lock Decisions**

When a lock happens, check the **Lock Screen**:

1. Look for the **ML Status Badge** below the lock title
2. Badge shows:
   - **"ML Decision (XX%)"** (Green) = ✅ ML was used
   - **"Rule-Based"** (Blue) = Rule-based fallback (ML not ready or confidence too low)
   - **"Safety Limit"** (Red) = Safety override (always enforced)

---

## 📊 **Step 3: Check Console Logs**

When ML makes a lock decision, you'll see detailed logs:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ ML LOCK DECISION (ENSEMBLE MODEL)
   Category: Social
   Decision: 🔒 LOCK
   Confidence: 75.0%
   Weights: Rule-based=50%, ML=50%
   Usage: 180min daily, 90min session
   Source: ensemble
   Reason: Ensemble prediction
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**What to look for:**
- ✅ `ML LOCK DECISION` = ML is active
- ✅ `Weights: Rule-based=X%, ML=Y%` = Ensemble is combining both
- ✅ `Confidence: XX%` = Should be ≥ 60% for ML to be used

---

## 🧪 **Step 4: Test with ML Pipeline Test Screen**

1. Navigate to: **Settings → ML Pipeline Test**
2. Use the test screen to:
   - Import CSV data (for demo)
   - Train model on test data
   - Test prediction pipeline
   - Verify output shows `source: 'ensemble'`

---

## ✅ **Verification Scenarios**

### Scenario 1: ML Not Ready (< 300 feedback)
- **Expected**: ML Status shows "Collecting Data"
- **Lock Screen**: Shows "Rule-Based" badge
- **Logs**: `⚠️ Model not fully trained, using rule-based`

### Scenario 2: ML Ready (300+ feedback, trained)
- **Expected**: ML Status shows "ML Active" (Green)
- **Lock Screen**: Shows "ML Decision (XX%)" badge when ML locks
- **Logs**: `✅ ML LOCK DECISION (ENSEMBLE MODEL)` with weights

### Scenario 3: ML Confidence Too Low (< 60%)
- **Expected**: Falls back to rule-based
- **Lock Screen**: Shows "Rule-Based" badge
- **Logs**: `⚠️ Ensemble confidence too low, using rule-based`

---

## 🎯 **Quick Test Script**

1. **Check ML Status**: Home page → ML Status Widget
2. **Trigger a Lock**: Use app until limit reached
3. **Verify Lock Screen**: Check ML Status Badge
4. **Check Logs**: Look for `✅ ML LOCK DECISION` or `✅ RULE-BASED LOCK DECISION`
5. **Verify Ensemble**: Logs should show weights (e.g., `Rule-based=50%, ML=50%`)

---

## 📝 **What Each Status Means**

| Status | Color | Meaning |
|--------|-------|---------|
| **ML Active** | 🟢 Green | ML is working! Using ensemble (ML + rule-based) |
| **ML Trained** | 🟠 Orange | Model trained but not activated yet (check criteria) |
| **Ready to Train** | 🔵 Blue | 300+ feedback samples, ready for training |
| **Collecting Data** | ⚪ Gray | < 300 samples, still collecting feedback |

---

## 🔍 **Troubleshooting**

### ML Status shows "ML Trained" but not "ML Active"
- **Check**: ML readiness criteria (300+ feedback, 5+ days, data diversity)
- **Solution**: Wait for more feedback or check `HybridLockManager.getMLStatus()`

### Lock Screen shows "Rule-Based" even when ML is active
- **Check**: ML confidence (should be ≥ 60%)
- **Check**: Console logs for `⚠️ Ensemble confidence too low`
- **Solution**: This is normal - ML only used when confidence is high

### No ML Status Badge on Lock Screen
- **Check**: Lock reason (daily_limit always uses rule-based)
- **Check**: ML source passed from MonitorService
- **Solution**: Only ML/ensemble locks show the badge

---

## ✅ **Success Criteria**

The ML pipeline is working correctly when:

1. ✅ ML Status Widget shows "ML Active" (Green)
2. ✅ Lock Screen shows "ML Decision (XX%)" badge for ML locks
3. ✅ Console logs show `✅ ML LOCK DECISION (ENSEMBLE MODEL)`
4. ✅ Logs show ensemble weights (e.g., `Rule-based=50%, ML=50%`)
5. ✅ Lock decisions use combined usage for monitored categories
6. ✅ Falls back to rule-based when ML confidence < 60%

---

## 🎉 **You're Done!**

If all checks pass, the ML pipeline is working correctly in production! 🚀

