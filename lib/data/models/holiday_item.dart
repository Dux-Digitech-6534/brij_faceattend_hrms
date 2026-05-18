import '../../core/utils/date_formats.dart';

class HolidayItem {
  const HolidayItem({
    required this.name,
    required this.holidayDate,
    this.description,
  });

  final String name;
  final DateTime holidayDate;
  final String? description;

  factory HolidayItem.fromJson(Map<String, dynamic> json) {
    return HolidayItem(
      name: '${json['name'] ?? ''}',
      holidayDate:
          DateTime.tryParse('${json['holiday_date'] ?? ''}') ?? DateTime.now(),
      description: json['description'] as String?,
    );
  }

  String get label => DateFormats.dayMonth.format(holidayDate.toLocal());
}
