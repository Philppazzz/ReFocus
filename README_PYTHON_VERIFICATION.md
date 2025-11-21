# Python Verification for ML Metrics

This document explains how to use Python (scikit-learn) to verify the accuracy of ML evaluation metrics calculated in the Flutter/Dart app.

## Overview

The Flutter app uses standard ML evaluation formulas that match scikit-learn. This Python script allows you to verify that the metrics are calculated correctly by comparing Dart results with Python's industry-standard implementation.

## Prerequisites

1. **Python 3.7+** installed on your system
2. **Required Python packages:**
   ```bash
   pip install pandas scikit-learn numpy
   ```

## How to Use

### Step 1: Train Model in Flutter App

1. Open the ML Pipeline Testing screen in your Flutter app
2. Select a dataset size (e.g., 144, 288, 504, 1000 samples)
3. Click "Train Model" and wait for training to complete

### Step 2: Export Test Data

1. After training, click **"Export for Python Verification"** button
2. The app will:
   - Generate predictions for the test set
   - Export to CSV file with format:
     ```
     category,daily_usage,session_usage,time_of_day,actual_label,predicted_label
     Social,120,30,14,Yes,No
     Games,200,60,20,Yes,Yes
     ...
     ```
3. Note the file path shown in the dialog

### Step 3: Run Python Verification

```bash
python verify_metrics.py "path/to/exported_test_data.csv"
```

**Example:**
```bash
python verify_metrics.py "C:\Users\YourName\AppData\Local\refocus_app\exported_test_data_1234567890.csv"
```

### Step 4: Compare Results

The Python script will output:
- **Accuracy**: Overall correctness
- **Precision**: Of predicted locks, how many were correct
- **Recall**: Of actual locks, how many were caught
- **F1-Score**: Harmonic mean of precision and recall
- **Confusion Matrix**: TP, TN, FP, FN breakdown

Compare these with the metrics shown in:
- Flutter app training results
- Model Analytics screen

## Expected Results

If the Dart implementation is correct, the Python metrics should **match exactly** (or be very close, within 0.01% due to floating-point precision).

### Example Output

```
======================================================================
  PYTHON VERIFICATION RESULTS (scikit-learn)
======================================================================

📊 Evaluation Metrics:
   Accuracy:  0.750000 (75.00%)
   Precision: 0.714286 (71.43%)
   Recall:    0.833333 (83.33%)
   F1-Score:  0.769231 (76.92%)

📋 Confusion Matrix:
   ┌─────────────────┬──────────────────┬──────────────────┐
   │                 │ Predicted Lock   │ Predicted No Lock│
   ├─────────────────┼──────────────────┼──────────────────┤
   │ Actual Lock     │   10 (TP)        │    2 (FN)        │
   ├─────────────────┼──────────────────┼──────────────────┤
   │ Actual No Lock  │    4 (FP)        │   12 (TN)        │
   └─────────────────┴──────────────────┴──────────────────┘

   • True Positive (TP):   10 - Correctly predicted Lock
   • True Negative (TN):   12 - Correctly predicted No Lock
   • False Positive (FP):   4 - Incorrectly predicted Lock
   • False Negative (FN):   2 - Incorrectly predicted No Lock

   Total Test Samples: 28
```

## Formulas Used

The Python script uses the **exact same formulas** as scikit-learn:

- **Accuracy**: `(TP + TN) / (TP + TN + FP + FN)`
- **Precision**: `TP / (TP + FP)`
- **Recall**: `TP / (TP + FN)`
- **F1-Score**: `2 * (Precision * Recall) / (Precision + Recall)`

These match the Dart implementation in `lib/ml/model_evaluator.dart`.

## Troubleshooting

### Error: "File not found"
- Make sure you copied the full file path from the Flutter app dialog
- On Windows, use quotes around the path if it contains spaces

### Error: "Missing required columns"
- The CSV should have columns: `category`, `daily_usage`, `session_usage`, `time_of_day`, `actual_label`, `predicted_label`
- Make sure you exported after training the model

### Metrics Don't Match
- Check that you're comparing the same test set
- The Dart app uses the same test set split (80/20 or 70/30) as shown in training results
- Small differences (<0.1%) are normal due to floating-point precision

## Why This Matters

1. **Verification**: Confirms Dart metrics match industry-standard Python libraries
2. **Confidence**: Ensures evaluation is accurate and professional
3. **Debugging**: Helps identify any calculation errors in the Dart implementation
4. **Professional Standard**: Uses the same metrics as scikit-learn, the gold standard in ML

## Integration with App

The export functionality is integrated into the ML Pipeline Testing screen:
- **Location**: ML Pipeline Testing → Testing section → "Export for Python Verification"
- **Requirements**: Model must be trained first
- **Output**: CSV file saved to app documents directory

## Next Steps

After verification:
1. If metrics match → Dart implementation is correct ✅
2. If metrics differ → Review calculation logic in `model_evaluator.dart`
3. Use Python results as reference for any discrepancies

