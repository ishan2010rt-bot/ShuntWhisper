import 'package:equatable/equatable.dart';

/// Sealed Result type representing either a successful computation [Ok] or a failure [Err].
sealed class Result<T> extends Equatable {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
        Ok(:final value) => value,
        Err() => null,
      };

  Failure? get failureOrNull => switch (this) {
        Ok() => null,
        Err(:final failure) => failure,
      };

  R fold<R>(R Function(T value) onOk, R Function(Failure failure) onErr) {
    return switch (this) {
      Ok(:final value) => onOk(value),
      Err(:final failure) => onErr(failure),
    };
  }

  @override
  List<Object?> get props => [];
}

final class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);

  @override
  List<Object?> get props => [value];
}

final class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);

  @override
  List<Object?> get props => [failure];
}

class Failure extends Equatable {
  final String code;
  final String message;
  final dynamic details;

  const Failure({
    required this.code,
    required this.message,
    this.details,
  });

  @override
  List<Object?> get props => [code, message, details];

  @override
  String toString() => 'Failure(code: $code, message: $message)';
}

