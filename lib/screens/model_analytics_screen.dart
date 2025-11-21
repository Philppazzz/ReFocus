import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:refocus_app/database_helper.dart';
import 'package:refocus_app/services/ensemble_model_service.dart';

/// Professional-grade model analytics screen
/// Displays comprehensive evaluation metrics with visualizations
class ModelAnalyticsScreen extends StatefulWidget {
  const ModelAnalyticsScreen({super.key});

  @override
  State<ModelAnalyticsScreen> createState() => _ModelAnalyticsScreenState();
}

class _ModelAnalyticsScreenState extends State<ModelAnalyticsScreen> {
  List<Map<String, dynamic>> _trainingHistory = [];
  Map<String, dynamic>? _currentMetrics;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMetrics();
  }

  Future<void> _loadMetrics() async {
    setState(() => _isLoading = true);
    
    try {
      // Load training history
      _trainingHistory = await DatabaseHelper.instance.getTrainingHistory(limit: 50);
      
      // Load current model metrics
      await EnsembleModelService.initialize();
      final userModel = EnsembleModelService.getUserTrainedModel();
      
      if (userModel != null && userModel.trainingDataCount > 0) {
        _currentMetrics = {
          'accuracy': userModel.accuracy,
          'precision': userModel.precision,
          'recall': userModel.recall,
          'f1_score': userModel.f1Score,
          'confusion_matrix': userModel.confusionMatrix,
          'training_samples': userModel.trainingDataCount,
          'last_trained': userModel.lastTrained,
        };
      }
    } catch (e) {
      print('⚠️ Error loading metrics: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(
          'Model Analytics',
          style: GoogleFonts.alice(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadMetrics,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _currentMetrics == null
              ? _buildNoModelCard()
              : RefreshIndicator(
                  onRefresh: _loadMetrics,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildOverviewCard(),
                        const SizedBox(height: 16),
                        _buildMetricsCard(),
                        const SizedBox(height: 16),
                        _buildConfusionMatrixCard(),
                        const SizedBox(height: 16),
                        if (_trainingHistory.isNotEmpty) ...[
                          _buildTrainingHistoryCard(),
                        ],
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildNoModelCard() {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(24),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.psychology_outlined, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No Model Trained Yet',
                style: GoogleFonts.alice(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Train the model first to see analytics',
                style: GoogleFonts.alice(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard() {
    final accuracy = (_currentMetrics!['accuracy'] as double) * 100;
    final precision = (_currentMetrics!['precision'] as double) * 100;
    final recall = (_currentMetrics!['recall'] as double) * 100;
    final f1Score = (_currentMetrics!['f1_score'] as double) * 100;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assessment, color: Colors.blue[700], size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Model Performance Overview',
                    style: GoogleFonts.alice(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMetricItem('Accuracy', accuracy, Colors.blue)),
                Expanded(child: _buildMetricItem('Precision', precision, Colors.green)),
                Expanded(child: _buildMetricItem('Recall', recall, Colors.orange)),
                Expanded(child: _buildMetricItem('F1-Score', f1Score, Colors.purple)),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetricsBarChart([accuracy, precision, recall, f1Score]),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricItem(String label, double value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.circle, color: color, size: 8),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.alice(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${value.toStringAsFixed(1)}%',
          style: GoogleFonts.alice(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricsBarChart(List<double> values) {
    return SizedBox(
      height: 200,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: 100,
              barTouchData: BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      const labels = ['Accuracy', 'Precision', 'Recall', 'F1-Score'];
                      final index = value.toInt();
                      if (index < 0 || index >= labels.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          labels[index],
                          style: GoogleFonts.alice(fontSize: 9, color: Colors.grey[600]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                    reservedSize: 35,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      return Text(
                        '${value.toInt()}%',
                        style: GoogleFonts.alice(fontSize: 9, color: Colors.grey[600]),
                      );
                    },
                    reservedSize: 35,
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[200]!,
                    strokeWidth: 1,
                  );
                },
              ),
              borderData: FlBorderData(show: false),
              barGroups: [
                BarChartGroupData(
                  x: 0,
                  barRods: [
                    BarChartRodData(
                      toY: values[0],
                      color: Colors.blue,
                      width: 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 1,
                  barRods: [
                    BarChartRodData(
                      toY: values[1],
                      color: Colors.green,
                      width: 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 2,
                  barRods: [
                    BarChartRodData(
                      toY: values[2],
                      color: Colors.orange,
                      width: 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: 3,
                  barRods: [
                    BarChartRodData(
                      toY: values[3],
                      color: Colors.purple,
                      width: 18,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricsCard() {
    final accuracy = (_currentMetrics!['accuracy'] as double) * 100;
    final precision = (_currentMetrics!['precision'] as double) * 100;
    final recall = (_currentMetrics!['recall'] as double) * 100;
    final f1Score = (_currentMetrics!['f1_score'] as double) * 100;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue[700], size: 24),
                const SizedBox(width: 12),
                Text(
                  'Detailed Metrics',
                  style: GoogleFonts.alice(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetricRow('Accuracy', accuracy, 'Overall correctness of predictions'),
            const Divider(),
            _buildMetricRow('Precision', precision, 'True positives / (True positives + False positives)'),
            const Divider(),
            _buildMetricRow('Recall', recall, 'True positives / (True positives + False negatives)'),
            const Divider(),
            _buildMetricRow('F1-Score', f1Score, 'Harmonic mean of Precision and Recall'),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, double value, String description) {
    Color color;
    if (value >= 80) {
      color = Colors.green;
    } else if (value >= 60) {
      color = Colors.orange;
    } else {
      color = Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.alice(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.alice(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              '${value.toStringAsFixed(1)}%',
              style: GoogleFonts.alice(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfusionMatrixCard() {
    final cm = _currentMetrics!['confusion_matrix'] as Map<String, int>;
    final tp = cm['true_positive'] ?? 0;
    final tn = cm['true_negative'] ?? 0;
    final fp = cm['false_positive'] ?? 0;
    final fn = cm['false_negative'] ?? 0;
    final total = tp + tn + fp + fn;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.grid_view, color: Colors.blue[700], size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Confusion Matrix',
                    style: GoogleFonts.alice(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // ✅ FIXED: Better table layout with proper constraints
            Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 64,
                ),
                child: Table(
                  border: TableBorder.all(color: Colors.grey[300]!, width: 1),
                  columnWidths: const {
                    0: FlexColumnWidth(1.2),
                    1: FlexColumnWidth(1.5),
                    2: FlexColumnWidth(1.5),
                  },
                  children: [
                    TableRow(
                      children: [
                        _buildCMCell('', Colors.grey[100]!, isHeader: true),
                        _buildCMCell('Predicted Lock', Colors.grey[100]!, isHeader: true),
                        _buildCMCell('Predicted No Lock', Colors.grey[100]!, isHeader: true),
                      ],
                    ),
                    TableRow(
                      children: [
                        _buildCMCell('Actual Lock', Colors.grey[100]!, isHeader: true),
                        _buildCMCell('$tp\n(TP)', Colors.green[100]!),
                        _buildCMCell('$fn\n(FN)', Colors.red[100]!),
                      ],
                    ),
                    TableRow(
                      children: [
                        _buildCMCell('Actual No Lock', Colors.grey[100]!, isHeader: true),
                        _buildCMCell('$fp\n(FP)', Colors.orange[100]!),
                        _buildCMCell('$tn\n(TN)', Colors.blue[100]!),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildCMLegend('TP: True Positive', Colors.green),
                _buildCMLegend('TN: True Negative', Colors.blue),
                _buildCMLegend('FP: False Positive', Colors.orange),
                _buildCMLegend('FN: False Negative', Colors.red),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Total Test Samples: $total',
                style: GoogleFonts.alice(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCMCell(String text, Color color, {bool isHeader = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      color: color,
      child: Center(
        child: Text(
          text,
          style: GoogleFonts.alice(
            fontSize: isHeader ? 12 : 14,
            fontWeight: isHeader ? FontWeight.bold : FontWeight.w600,
            color: Colors.black87,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.visible,
        ),
      ),
    );
  }

  Widget _buildCMLegend(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withOpacity(0.3),
            border: Border.all(color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.alice(fontSize: 10, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildTrainingHistoryCard() {
    if (_trainingHistory.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.blue[700], size: 24),
                const SizedBox(width: 12),
                Text(
                  'Training History',
                  style: GoogleFonts.alice(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey[200]!,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() >= _trainingHistory.length) return const Text('');
                          final index = _trainingHistory.length - value.toInt() - 1;
                          if (index < 0 || index >= _trainingHistory.length) return const Text('');
                          final timestamp = _trainingHistory[index]['timestamp'] as int;
                          final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${date.day}/${date.month}',
                              style: GoogleFonts.alice(fontSize: 10, color: Colors.grey[600]),
                            ),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}%',
                            style: GoogleFonts.alice(fontSize: 10, color: Colors.grey[600]),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: List.generate(
                        _trainingHistory.length,
                        (index) {
                          final accuracy = (_trainingHistory[index]['accuracy'] as double) * 100;
                          return FlSpot(index.toDouble(), accuracy);
                        },
                      ),
                      isCurved: true,
                      color: Colors.blue,
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(show: false),
                    ),
                  ],
                  minY: 0,
                  maxY: 100,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

