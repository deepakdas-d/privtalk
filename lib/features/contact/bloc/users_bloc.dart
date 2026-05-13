// lib/features/contact/bloc/users_bloc.dart

import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/user_model.dart';
import '../repository/users_repository.dart';
import 'users_event.dart';
import 'users_state.dart';

class UsersBloc extends Bloc<UsersEvent, UsersState> {
  final UsersRepository repository;

  UsersBloc(this.repository) : super(UsersInitial()) {
    on<FetchUsers>(_onFetchUsers);
  }

  Future<void> _onFetchUsers(FetchUsers event, Emitter<UsersState> emit) async {
    emit(UsersLoading());

    await emit.forEach<List<UserModel>>(
      repository.getUsers(),
      onData: (users) => UsersLoaded(users),
      onError: (error, _) => UsersError(error.toString()),
    );
  }
}
