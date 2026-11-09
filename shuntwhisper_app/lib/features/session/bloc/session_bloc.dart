import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shuntwhisper_camera/src/camera_service.dart';
import '../../../data/api/shuntwhisper_api.dart';
import 'session_state.dart';
import 'session_event.dart';
import 'session_effect.dart';
import 'session_reducer.dart';
import 'effect_runner.dart';

class SessionBloc extends Bloc<SessionEvent, SessionState> {
  final CameraService cameraService;
  final ShuntWhisperApi api;
  late final EffectRunner _effectRunner;
  StreamSubscription? _alignmentSubscription;

  SessionBloc({
    required this.cameraService,
    required this.api,
    required String initialSessionId,
  }) : super(SessionState.initial(initialSessionId)) {
    _effectRunner = EffectRunner(
      cameraService: cameraService,
      api: api,
      dispatch: add,
    );

    on<SessionEvent>(_onEvent);

    // Subscribe to camera alignment updates
    _alignmentSubscription = cameraService.alignmentStream.listen((alignment) {
      add(AlignmentUpdated(alignment));
    });
  }

  Future<void> _onEvent(SessionEvent event, Emitter<SessionState> emit) async {
    final (nextState, effects) = SessionReducer.reduce(state, event);
    emit(nextState);

    for (final effect in effects) {
      await _effectRunner.run(effect);
    }
  }

  @override
  Future<void> close() {
    _alignmentSubscription?.cancel();
    return super.close();
  }
}

