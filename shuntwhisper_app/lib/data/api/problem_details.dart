import 'package:equatable/equatable.dart';

/// RFC 7807 Problem Details representation.
class ProblemDetails extends Equatable {
  final String type;
  final String title;
  final int status;
  final String? detail;
  final String code;
  final String? instance;

  const ProblemDetails({
    this.type = 'about:blank',
    required this.title,
    required this.status,
    this.detail,
    required this.code,
    this.instance,
  });

  factory ProblemDetails.fromJson(Map<String, dynamic> json) => ProblemDetails(
        type: json['type'] ?? 'about:blank',
        title: json['title'] ?? 'Unknown Error',
        status: (json['status'] as num?)?.toInt() ?? 500,
        detail: json['detail'],
        code: json['code'] ?? 'UNKNOWN',
        instance: json['instance'],
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        'status': status,
        if (detail != null) 'detail': detail,
        'code': code,
        if (instance != null) 'instance': instance,
      };

  @override
  List<Object?> get props => [type, title, status, detail, code, instance];
}

