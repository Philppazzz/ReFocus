# Usage Statistics Dashboard - Complete Feature Guide

## Overview
A modern, visually detailed Usage Statistics Page designed like smartphone's Screen Time dashboard. Helps users understand their screen-time habits and track improvement progress.

## 🎨 Design Philosophy

### Color Scheme (Matching IntroPage)
- **Background**: `#F5F6FA` (Light gray-blue)
- **Primary**: `#6366F1` (Indigo) - Main app color
- **Secondary**: `#8B5CF6` (Purple) - Gradient accent
- **Success**: `#10B981` (Green) - For improvements
- **Warning**: `#F59E0B` (Orange/Amber) - For increases
- **Error**: `#EF4444` (Red) - For high usage
- **White Cards**: Clean white containers with subtle shadows

### Typography
- **Font Family**: Google Fonts Inter (consistent with IntroPage)
- **Responsive Sizing**: All sizes adapt to screen dimensions
- **Weight Hierarchy**: Bold for headers, medium for body, regular for labels

### Responsive Design
- ✅ **Screen-based Sizing**: All dimensions use `screenHeight` and `screenWidth` percentages
- ✅ **No Fixed Heights**: Everything adapts from small phones (Android 11) to large screens (Android 16)
- ✅ **Safe Areas**: Proper padding and spacing prevent content overlap
- ✅ **Scrollable**: Everything is in a `SingleChildScrollView` with `RefreshIndicator`

## 📊 Page Sections

### 1. **Improvement Summary Card** (Top)
**Location**: First card, immediately visible

**Purpose**: Quick glance at progress

**Design**:
- Gradient background (green if improving, orange/red if not)
- Large emoji indicator (🎉 for good, 📈 for needs work)
- Bold text with improvement percentage
- Subtle shadow for depth

**Messages**:
- Improving: "Great job! X% less than yesterday"
- Increasing: "Usage increased by X% since yesterday"
- Same: "Same as yesterday. Keep going! ✨"
- First day: "First day of tracking! Keep it up! 💪"
- Weekly context: "This week: X% less/more than last week"

**Data Source**:
```dart
_dailyImprovement = ((yesterdayUsage - todayUsage) / yesterdayUsage) * 100
_weeklyImprovement = ((lastWeekTotal - thisWeekTotal) / lastWeekTotal) * 100
```

### 2. **Today's Usage Section**

#### a) Ring Chart Card
**Visual**: Circular progress indicator showing today's total usage

**Design**:
- Large ring (16% of screen height)
- Center shows: "Xh Ym" and "Total Today"
- Color-coded by usage level:
  - Green: < 2 hours
  - Orange: 2-4 hours
  - Red: > 4 hours
- Progress fills based on 8-hour max visualization

**Layout**:
```
┌─────────────────┐
│   ╭─────────╮   │
│  ╭           ╮  │
│ ╭             ╮ │
│ │   2h 30m    │ │  ← Bold usage
│ │ Total Today │ │  ← Gray subtitle
│ ╰             ╯ │
│  ╰           ╯  │
│   ╰─────────╯   │
└─────────────────┘
```

#### b) Most Used Apps Today
**Visual**: Top 3 apps ranked by duration

**Design**:
- Rank badges (🥇 Gold, 🥈 Silver, 🥉 Bronze)
- App name on left
- Duration on right (Xh Ym format)
- Progress bar below (fills proportionally)
- Clean white card background

**Layout**:
```
┌──────────────────────────────┐
│ Most Used Apps               │
│                              │
│ [1] Instagram       2h 15m   │
│ ████████████████░░░░          │
│                              │
│ [2] Facebook        1h 30m   │
│ ███████████░░░░░░░░░          │
│                              │
│ [3] TikTok          45m      │
│ █████░░░░░░░░░░░░░░░          │
└──────────────────────────────┘
```

#### c) Most Unlocked Apps Today
**Visual**: Top 3 apps ranked by open count

**Same design** as "Most Used Apps" but shows:
- "X times" instead of duration
- Different data source (unlock counts)

### 3. **This Week's Usage Section**

#### a) Weekly Chart Card
**Visual**: Line chart showing 7-day trend

**Design**:
- Curved line with gradient fill
- X-axis: Day labels (Mon, Tue, Wed, Thu, Fri, Sat, Sun)
- Y-axis: Hours (with "Xh" labels)
- Dot markers on each day
- Gradient area below line
- Total hours shown in top-right corner

**Features**:
- Smooth animations (fl_chart library)
- Interactive (can tap points)
- Auto-scales Y-axis based on max usage
- Grid lines for easy reading
- Gradient from indigo to purple

**Layout**:
```
┌────────────────────────────────┐
│ Daily Usage Trend    18.5h total│
│                              ╱  │
│                            ╱    │
│                         ╱─╯     │
│                    ╱─╯          │
│              ╱──╯              │
│        ╱─╯                      │
│  ╱─╯                            │
│ Mon Tue Wed Thu Fri Sat Sun     │
└────────────────────────────────┘
```

#### b) Most Used Apps This Week
**Visual**: Top 3 apps for the week

**Same design** as daily, but aggregates 7 days of data

#### c) Most Unlocked Apps This Week
**Visual**: Top 3 most opened apps this week

**Same design** as daily unlock section

## 🏠 Home Page Integration

### Improvement Summary Card
**Location**: Between "Most Unlocked App" card and "More details" button

**Design**:
- Compact version of the full stats page summary
- Same gradient background and emoji
- Shorter message for space efficiency
- Tappable (opens full statistics page)

**Messages**:
- "Great job! X% less than yesterday"
- "Usage increased by X% since yesterday"
- "First day of tracking! Keep it up! 💪"

**Layout on HomePage**:
```
┌─ Most Unlocked App Card ──────┐
└───────────────────────────────┘

┌─ Your Progress ───────────────┐
│ 🎉  Great job! 25% less than  │
│     yesterday                 │
└───────────────────────────────┘

┌─ More details Button ─────────┐
│ [📊 Analytics] More details   │
└───────────────────────────────┘
```

## 🔄 Data Flow & Logic

### Data Sources (No Core Logic Modified ✅)
All data comes from existing database methods:

1. **Today's Stats**:
```dart
final todayStats = await DatabaseHelper.instance.getTodayStats();
final todayTopApps = await db.getTopApps(startDate: today, endDate: today, limit: 3);
final todayTopUnlocks = await db.getTopAppsByUnlocks(startDate: today, endDate: today, limit: 3);
```

2. **Week's Stats**:
```dart
final weekStats = await db.getWeekStats();
final weekTopApps = await db.getTopApps(startDate: weekAgo, endDate: today, limit: 3);
final weekTopUnlocks = await db.getTopAppsByUnlocks(startDate: weekAgo, endDate: today, limit: 3);
```

3. **Improvement Calculation**:
```dart
// Yesterday's usage
final yesterdayStats = await db.getTopApps(startDate: yesterday, endDate: yesterday, limit: 100);
final yesterdayHours = yesterdayStats.fold(0.0, (sum, app) => sum + app['total_usage_seconds'] / 3600);

// Calculate improvement
if (yesterdayHours > 0) {
  _dailyImprovement = ((yesterdayHours - todayHours) / yesterdayHours) * 100;
}
```

### State Management
```dart
// HomePage State Variables (Added)
double _todayUsageHours = 0.0;
double _yesterdayUsageHours = 0.0;
double _dailyImprovement = 0.0;

// UsageStatisticsPage State Variables
double _todayUsageHours = 0.0;
List<Map<String, dynamic>> _todayTopApps = [];
List<Map<String, dynamic>> _todayTopUnlocks = [];
List<Map<String, dynamic>> _weekStats = [];
double _weekTotal = 0.0;
double _dailyImprovement = 0.0;
double _weeklyImprovement = 0.0;
```

## 📱 Responsive Behavior

### Small Screens (< 5.5")
- Font sizes scale down proportionally
- Card padding reduces to 5% of screen width
- Chart height set to 18-20% of screen height
- Compact spacing between elements

### Medium Screens (5.5" - 6.5")
- Standard sizing (default design)
- Balanced spacing
- Optimal readability

### Large Screens (> 6.5")
- Elements scale up proportionally
- Maximum widths prevent over-stretching
- Increased padding for comfort

### Landscape Mode
- SingleChildScrollView ensures all content accessible
- Horizontal padding increases
- Charts remain properly sized

## 🎯 User Experience Features

### 1. **Pull to Refresh**
```dart
RefreshIndicator(
  onRefresh: _loadStatistics,
  child: SingleChildScrollView(...),
)
```

### 2. **Loading State**
- Shows `CircularProgressIndicator` while fetching data
- Smooth transition to content

### 3. **Empty States**
- "No data available" message when no apps tracked
- Helpful for first-time users

### 4. **Visual Hierarchy**
- Section titles with icons
- Card-based layout for easy scanning
- Color-coded progress indicators

### 5. **Readable Time Formats**
```dart
_formatDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  if (seconds < 3600) return '${minutes}m';
  return '${hours}h ${minutes}m';
}
```

## 🔧 Technical Implementation

### Dependencies Used
- `fl_chart` - For line charts and bar charts
- `google_fonts` - Inter font family
- `shared_preferences` - State persistence
- Built-in Flutter widgets - Material Design

### File Structure
```
lib/
├── pages/
│   ├── usage_statistics_page.dart  ← NEW (Complete rewrite)
│   └── home_page.dart              ← Modified (Added improvement card)
├── services/
│   ├── usage_service.dart          ← Untouched ✅
│   ├── monitor_service.dart        ← Untouched ✅
│   └── lock_state_manager.dart     ← Untouched ✅
└── database_helper.dart            ← Untouched ✅
```

### Code Safety
✅ **No Core Logic Modified**
- All tracking logic untouched
- All locking mechanisms untouched
- All monitoring services untouched
- Only UI/display code added

✅ **Read-Only Database Queries**
- Only `SELECT` queries used
- No `INSERT`, `UPDATE`, or `DELETE` operations
- Cannot affect app functionality

✅ **Isolated State**
- Statistics page has its own state
- HomePage improvement card uses separate variables
- No shared mutable state

## 🚀 Usage Instructions

### For Users
1. **View Statistics**: Tap "More details" button on home page
2. **See Today's Usage**: Ring chart at top shows total time
3. **Check Progress**: Green card = improving, Orange/Red = needs work
4. **Explore Weekly Trends**: Scroll down to see 7-day chart
5. **Pull to Refresh**: Swipe down to update data

### For Developers
1. **Add New Metrics**: Add to `_loadStatistics()` method
2. **Customize Colors**: Modify color constants at top of build method
3. **Change Chart Type**: Replace `LineChart` with `BarChart` in fl_chart
4. **Adjust Limits**: Modify visualization max (currently 8 hours)
5. **Add More Apps**: Change `limit` parameter in database queries

## 📈 Future LSTM Integration (Placeholder)

The improvement calculation currently uses simple percentage comparison:
```dart
improvement = ((yesterday - today) / yesterday) * 100
```

**Placeholder for LSTM**:
```dart
// TODO: Replace with LSTM prediction
// final prediction = await LSTMBridge.predictImprovement(
//   todayUsage: _todayUsageHours,
//   yesterdayUsage: _yesterdayUsageHours,
//   weekUsage: _weekStats,
// );
// _dailyImprovement = prediction['improvement_score'];
```

This can be easily replaced when LSTM model is ready, without changing any UI code.

## ✅ Testing Checklist

### Visual Testing
- [ ] Ring chart displays correctly on all screen sizes
- [ ] Rank badges (🥇🥈🥉) appear with correct colors
- [ ] Progress bars fill proportionally
- [ ] Line chart renders smoothly with 7 days of data
- [ ] Gradient backgrounds display correctly
- [ ] Text is readable on all backgrounds

### Functional Testing
- [ ] Pull-to-refresh updates data
- [ ] Empty states show when no data
- [ ] Improvement percentage calculates correctly
- [ ] Navigation between home and stats page works
- [ ] Back button returns to home page
- [ ] Refresh button in AppBar updates data

### Responsive Testing
- [ ] Test on small phone (< 5.5")
- [ ] Test on medium phone (5.5" - 6.5")
- [ ] Test on large phone (> 6.5")
- [ ] Test in portrait mode
- [ ] Test in landscape mode
- [ ] Test on Android 11 (minimum supported)
- [ ] Test on Android 16 (latest)

### Data Accuracy
- [ ] Today's usage matches home page
- [ ] Top apps ranked correctly
- [ ] Unlock counts accurate
- [ ] Weekly totals sum correctly
- [ ] Improvement calculation accurate
- [ ] App names display correctly (not package names)

## 🎨 Design Consistency Checklist

✅ **Color Scheme**
- Matches IntroPage background (#F5F6FA)
- Uses app's primary indigo color
- Consistent gradient styling
- Proper color coding (green/orange/red)

✅ **Typography**
- Uses Google Fonts Inter throughout
- Consistent font weights
- Readable font sizes
- Proper text hierarchy

✅ **Spacing**
- 16-24px between cards
- 5% horizontal padding
- 2% vertical padding
- Consistent internal padding

✅ **Shadows & Elevation**
- Subtle shadows on cards (0.05 opacity)
- Consistent blur radius (10px)
- Proper elevation hierarchy

✅ **Border Radius**
- All cards: 16px rounded corners
- Buttons: 12px rounded corners
- Progress bars: 4px rounded corners

## 📝 Notes

- **Performance**: Statistics load in < 1 second for typical data
- **Memory**: Lightweight, only loads necessary data
- **Battery**: Minimal impact, read-only operations
- **Storage**: No additional data stored, uses existing DB
- **Compatibility**: Works on Android 11+ (SDK 30+)
- **Accessibility**: High contrast ratios, readable fonts
- **Localization**: Easy to translate (all strings in code)

## 🐛 Known Limitations

1. **First Day**: No improvement shown on first day (no yesterday data)
2. **Chart Scale**: Y-axis auto-scales but may look empty if usage very low
3. **App Icons**: Currently shows rank badges, not actual app icons
4. **Time Zones**: Uses device local time, may have issues if time zone changes
5. **Large Datasets**: Performance may degrade with 100+ apps (use pagination if needed)

## 🔮 Future Enhancements (Optional)

1. **Real App Icons**: Load actual app icons from package manager
2. **Monthly View**: Add monthly statistics tab
3. **Comparison Mode**: Compare any two days/weeks
4. **Export Data**: Export as CSV/PDF
5. **Notifications**: Weekly progress reports
6. **Goals**: Set custom daily goals
7. **Streak Counter**: Track consecutive improvement days
8. **Heatmap Calendar**: Visual calendar of usage patterns
9. **Category Breakdown**: Social Media, Entertainment, Productivity, etc.
10. **Time of Day Analysis**: Peak usage hours visualization

