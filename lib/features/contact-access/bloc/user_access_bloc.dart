import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_event.dart';
import 'package:privtalk/features/contact-access/bloc/user_access_state.dart';

import '../repository/user_access_repository.dart';

class UserAccessBloc extends Bloc<UserAccessEvent, UserAccessState> {
  final UserAccessRepository repository;

  UserAccessBloc({required this.repository}) : super(UserAccessInitial()) {
    on<LoadUserEvent>(_onLoadUser);
  }

  Future<void> _onLoadUser(
    LoadUserEvent event,
    Emitter<UserAccessState> emit,
  ) async {
    try {
      emit(UserAccessLoading());

      final user = await repository.fetchUser(event.uid);

      emit(UserAccessLoaded(user));
    } catch (e) {
      emit(UserAccessError(e.toString()));
    }
  }
}
