import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:privtalk/features/auth/model/auth_model.dart';
import 'package:privtalk/features/auth/repository/auth_repository.dart';
import 'package:privtalk/features/profile/bloc/profile_bloc.dart';
import 'package:privtalk/features/profile/bloc/profile_event.dart';
import 'package:privtalk/features/profile/bloc/profile_state.dart';
import 'package:privtalk/features/profile/repository/profile_repository.dart';
import 'package:privtalk/utils/widgets/auth_field.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  // ── photo picker ────────────────────────────────────────────────────────────
  Future<void> _pickAndUpload(BuildContext context) async {
    final source = await _showSourceSheet(context);
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 90, // pre-pick quality (Cloudinary compresses further)
      maxWidth: 1200,
    );
    if (picked == null || !context.mounted) return;

    // Validate extension
    final ext = picked.path.split('.').last.toLowerCase();
    if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext)) {
      ScaffoldMessenger.of(context).showSnackBar(
        _snack('Only JPG, PNG, or WEBP images are supported.', error: true),
      );
      return;
    }

    context.read<ProfileBloc>().add(UploadProfilePhoto(filePath: picked.path));
  }

  Future<ImageSource?> _showSourceSheet(BuildContext context) {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: const Color(0xFF1C1C26),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(
                Icons.photo_camera_rounded,
                color: Color(0xFF6C63FF),
              ),
              title: const Text(
                'Camera',
                style: TextStyle(color: Color(0xFFF0F0FF)),
              ),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library_rounded,
                color: Color(0xFF6C63FF),
              ),
              title: const Text(
                'Gallery',
                style: TextStyle(color: Color(0xFFF0F0FF)),
              ),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────────
  SnackBar _snack(String msg, {bool error = false}) => SnackBar(
    content: Text(msg),
    backgroundColor: error ? const Color(0xFFFF5F7E) : const Color(0xFF6C63FF),
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  );

  // ── build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ProfileBloc(ProfileRepository())..add(LoadProfile()),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            onPressed: () => context.go('/home'),
          ),
          actions: [
            BlocBuilder<ProfileBloc, ProfileState>(
              builder: (context, state) {
                final canEdit =
                    state is ProfileLoaded || state is ProfileUpdateSuccess;
                if (!canEdit) return const SizedBox.shrink();
                return TextButton(
                  onPressed: () => setState(() => _editing = !_editing),
                  child: Text(
                    _editing ? 'Cancel' : 'Edit',
                    style: const TextStyle(color: Color(0xFF6C63FF)),
                  ),
                );
              },
            ),
          ],
        ),
        body: BlocConsumer<ProfileBloc, ProfileState>(
          listener: (context, state) {
            if (state is ProfileUpdateSuccess) {
              setState(() => _editing = false);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(_snack('Profile updated!'));
            }
            if (state is ProfilePhotoUploadSuccess) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(_snack('Photo updated!'));
            }
            if (state is ProfileFailure) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(_snack(state.message, error: true));
            }
          },
          builder: (context, state) {
            if (state is ProfileLoading) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF6C63FF)),
              );
            }

            final UserModel? user = state is ProfileLoaded
                ? state.user
                : state is ProfileUpdateSuccess
                ? state.user
                : state is ProfileUpdating
                ? state.user
                : state is ProfilePhotoUploading
                ? state.user
                : state is ProfilePhotoUploadSuccess
                ? state.user
                : state is ProfileFailure
                ? state.user
                : null;

            if (user == null) {
              return const Center(
                child: Text(
                  'Could not load profile.',
                  style: TextStyle(color: Color(0xFF8888AA)),
                ),
              );
            }

            if (_editing && _name.text.isEmpty) {
              _name.text = user.name;
              _phone.text = user.phone;
            }

            final isUploadingPhoto = state is ProfilePhotoUploading;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                children: [
                  _buildAvatar(context, user, isUploadingPhoto),
                  const SizedBox(height: 28),
                  if (!_editing)
                    _buildInfoCard(user)
                  else
                    _buildEditForm(context, state),
                  const SizedBox(height: 32),
                  _buildLogoutButton(context),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── avatar with upload overlay ───────────────────────────────────────────────
  Widget _buildAvatar(BuildContext context, UserModel user, bool isUploading) {
    final initials = user.name.trim().isNotEmpty
        ? user.name
              .trim()
              .split(' ')
              .map((e) => e[0])
              .take(2)
              .join()
              .toUpperCase()
        : '?';

    return Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            // ── avatar circle ──
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF4A44CC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipOval(
                child: isUploading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : user.photoUrl != null
                    ? CachedNetworkImage(
                        imageUrl: user.photoUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        errorWidget: (_, _, _) => Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
              ),
            ),

            // ── camera button ──
            if (!isUploading)
              GestureDetector(
                onTap: () => _pickAndUpload(context),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFF13131A),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          user.name,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Color(0xFFF0F0FF),
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }

  // ── info card (view mode) ────────────────────────────────────────────────────
  Widget _buildInfoCard(UserModel user) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C26),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(
        children: [
          _infoRow(Icons.mail_outline_rounded, 'Email', user.email),
          const Divider(color: Color(0xFF2A2A3A), height: 28),
          _infoRow(
            Icons.phone_outlined,
            'Phone',
            user.phone.isNotEmpty ? user.phone : '—',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Row(
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: const Color(0xFF6C63FF), size: 18),
      ),
      const SizedBox(width: 14),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF8888AA), fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFFF0F0FF),
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ],
  );

  // ── edit form ────────────────────────────────────────────────────────────────
  Widget _buildEditForm(BuildContext context, ProfileState state) {
    final isUpdating = state is ProfileUpdating;
    return Column(
      children: [
        AuthField(
          controller: _name,
          hint: 'Full name',
          icon: Icons.person_outline_rounded,
        ),
        const SizedBox(height: 14),
        AuthField(
          controller: _phone,
          hint: 'Phone number',
          icon: Icons.phone_outlined,
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: isUpdating
              ? null
              : () => context.read<ProfileBloc>().add(
                  UpdateProfile(
                    name: _name.text.trim(),
                    phone: _phone.text.trim(),
                  ),
                ),
          child: isUpdating
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text('Save Changes'),
        ),
      ],
    );
  }

  // ── logout ───────────────────────────────────────────────────────────────────
  Widget _buildLogoutButton(BuildContext context) {
    final repo = AuthRepository();
    return OutlinedButton.icon(
      onPressed: () async {
        await repo.logout();
        if (context.mounted) context.go('/login');
      },
      icon: const Icon(
        Icons.logout_rounded,
        size: 18,
        color: Color(0xFFFF5F7E),
      ),
      label: const Text('Sign Out', style: TextStyle(color: Color(0xFFFF5F7E))),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 52),
        side: const BorderSide(color: Color(0xFFFF5F7E), width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
