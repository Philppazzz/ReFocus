#!/usr/bin/env python3
"""
Python Verification Script for ML Model Metrics
Uses scikit-learn to calculate standard ML evaluation metrics
Compares with Dart implementation for accuracy verification

Usage:
    python verify_metrics.py exported_test_data.csv
"""

import sys
import pandas as pd
import numpy as np
from sklearn.metrics import (
    accuracy_score,
    precision_score,
    recall_score,
    f1_score,
    confusion_matrix,
    classification_report
)

def calculate_metrics(y_true, y_pred, pos_label='Yes'):
    """
    Calculate comprehensive ML evaluation metrics using scikit-learn
    This matches the standard formulas used in professional ML evaluation
    """
    # Convert to numpy arrays for compatibility
    y_true = np.array(y_true)
    y_pred = np.array(y_pred)
    
    # Calculate confusion matrix
    cm = confusion_matrix(y_true, y_pred, labels=[pos_label, 'No'])
    
    # Extract TP, TN, FP, FN from confusion matrix
    # For binary classification with labels=['Yes', 'No']:
    # cm[0][0] = TP (Yes predicted as Yes)
    # cm[0][1] = FN (Yes predicted as No)
    # cm[1][0] = FP (No predicted as Yes)
    # cm[1][1] = TN (No predicted as No)
    tp = int(cm[0][0]) if cm.shape == (2, 2) else 0
    fn = int(cm[0][1]) if cm.shape == (2, 2) else 0
    fp = int(cm[1][0]) if cm.shape == (2, 2) else 0
    tn = int(cm[1][1]) if cm.shape == (2, 2) else 0
    
    # Calculate metrics using scikit-learn (industry standard)
    accuracy = accuracy_score(y_true, y_pred)
    precision = precision_score(y_true, y_pred, pos_label=pos_label, zero_division=0)
    recall = recall_score(y_true, y_pred, pos_label=pos_label, zero_division=0)
    f1 = f1_score(y_true, y_pred, pos_label=pos_label, zero_division=0)
    
    return {
        'accuracy': accuracy,
        'precision': precision,
        'recall': recall,
        'f1_score': f1,
        'confusion_matrix': {
            'true_positive': tp,
            'true_negative': tn,
            'false_positive': fp,
            'false_negative': fn
        },
        'total_samples': len(y_true),
        'tp': tp,
        'tn': tn,
        'fp': fp,
        'fn': fn
    }

def print_results(metrics, title="PYTHON VERIFICATION RESULTS"):
    """Print formatted results"""
    print("=" * 70)
    print(f"  {title} (scikit-learn)")
    print("=" * 70)
    print()
    print("📊 Evaluation Metrics:")
    print(f"   Accuracy:  {metrics['accuracy']:.6f} ({metrics['accuracy']*100:.2f}%)")
    print(f"   Precision: {metrics['precision']:.6f} ({metrics['precision']*100:.2f}%)")
    print(f"   Recall:    {metrics['recall']:.6f} ({metrics['recall']*100:.2f}%)")
    print(f"   F1-Score:  {metrics['f1_score']:.6f} ({metrics['f1_score']*100:.2f}%)")
    print()
    print("📋 Confusion Matrix:")
    cm = metrics['confusion_matrix']
    print(f"   ┌─────────────────┬──────────────────┬──────────────────┐")
    print(f"   │                 │ Predicted Lock   │ Predicted No Lock│")
    print(f"   ├─────────────────┼──────────────────┼──────────────────┤")
    print(f"   │ Actual Lock     │ {cm['true_positive']:4d} (TP)         │ {cm['false_negative']:4d} (FN)         │")
    print(f"   ├─────────────────┼──────────────────┼──────────────────┤")
    print(f"   │ Actual No Lock  │ {cm['false_positive']:4d} (FP)         │ {cm['true_negative']:4d} (TN)         │")
    print(f"   └─────────────────┴──────────────────┴──────────────────┘")
    print()
    print(f"   • True Positive (TP):  {cm['true_positive']:4d} - Correctly predicted Lock")
    print(f"   • True Negative (TN):  {cm['true_negative']:4d} - Correctly predicted No Lock")
    print(f"   • False Positive (FP): {cm['false_positive']:4d} - Incorrectly predicted Lock")
    print(f"   • False Negative (FN): {cm['false_negative']:4d} - Incorrectly predicted No Lock")
    print()
    print(f"   Total Test Samples: {metrics['total_samples']}")
    print()
    print("=" * 70)
    print()

def verify_csv_format(df):
    """Verify CSV has required columns"""
    required_columns = ['actual_label', 'predicted_label']
    missing = [col for col in required_columns if col not in df.columns]
    if missing:
        print(f"❌ ERROR: Missing required columns: {', '.join(missing)}")
        print(f"   Available columns: {', '.join(df.columns)}")
        return False
    return True

def main():
    if len(sys.argv) < 2:
        print("Usage: python verify_metrics.py <exported_test_data.csv>")
        print()
        print("Expected CSV format:")
        print("  category,daily_usage,session_usage,time_of_day,actual_label,predicted_label")
        print()
        print("Example:")
        print("  python verify_metrics.py exported_test_data.csv")
        sys.exit(1)
    
    csv_file = sys.argv[1]
    
    try:
        # Read CSV file
        print(f"📂 Loading data from: {csv_file}")
        df = pd.read_csv(csv_file)
        print(f"✅ Loaded {len(df)} samples")
        print()
        
        # Verify format
        if not verify_csv_format(df):
            sys.exit(1)
        
        # Extract labels
        y_true = df['actual_label'].tolist()
        y_pred = df['predicted_label'].tolist()
        
        # Validate labels
        valid_labels = ['Yes', 'No']
        invalid_true = [label for label in y_true if label not in valid_labels]
        invalid_pred = [label for label in y_pred if label not in valid_labels]
        
        if invalid_true:
            print(f"⚠️  WARNING: Invalid actual labels found: {set(invalid_true)}")
            print("   Expected: 'Yes' or 'No'")
        if invalid_pred:
            print(f"⚠️  WARNING: Invalid predicted labels found: {set(invalid_pred)}")
            print("   Expected: 'Yes' or 'No'")
        
        # Check label distribution
        print("📊 Label Distribution:")
        true_dist = pd.Series(y_true).value_counts()
        pred_dist = pd.Series(y_pred).value_counts()
        print(f"   Actual:   Yes={true_dist.get('Yes', 0)}, No={true_dist.get('No', 0)}")
        print(f"   Predicted: Yes={pred_dist.get('Yes', 0)}, No={pred_dist.get('No', 0)}")
        print()
        
        # Calculate metrics
        print("🔍 Calculating metrics using scikit-learn...")
        metrics = calculate_metrics(y_true, y_pred)
        
        # Print results
        print_results(metrics)
        
        # Additional classification report
        print("📄 Detailed Classification Report:")
        print(classification_report(y_true, y_pred, labels=['Yes', 'No'], target_names=['Lock', 'No Lock']))
        
        # Save results to JSON for comparison
        import json
        output_file = csv_file.replace('.csv', '_python_metrics.json')
        with open(output_file, 'w') as f:
            json.dump(metrics, f, indent=2)
        print(f"💾 Results saved to: {output_file}")
        print()
        print("✅ Verification complete!")
        
    except FileNotFoundError:
        print(f"❌ ERROR: File not found: {csv_file}")
        sys.exit(1)
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()

