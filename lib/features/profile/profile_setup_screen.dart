import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:in_range/core/session/app_session.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Profile: up to 6 local photos, bio, DOB, gender, preference, interests + free text.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  final _customInterest = TextEditingController();
  final _year = TextEditingController(
    text: '${DateTime.now().year - 25}',
  );
  String _gender = 'prefer-not-to-say';
  String _pref = 'women';
  final _selectedInterests = <String>{};
  final _photos = <String>[];
  String? _error;
  bool _busy = false;

  static const _genders = [
    'male',
    'female',
    'non-binary',
    'prefer-not-to-say',
    'other',
  ];
  static const _prefs = ['men', 'women'];
  static const _interestPool = [
    'Coffee',
    'Music',
    'Hiking',
    'Food',
    'Art',
    'Fitness',
    'Travel',
    'Gaming',
    'Movies',
    'Dogs',
    'Cats',
    'Tech',
  ];

  @override
  void initState() {
    super.initState();
    final s = ref.read(sessionControllerProvider);
    if (s.displayName != null) _name.text = s.displayName!;
    if (s.bio != null) _bio.text = s.bio!;
    if (s.customInterest != null) _customInterest.text = s.customInterest!;
    if (s.birthYear != null) _year.text = '${s.birthYear}';
    _photos.addAll(s.photoPaths);
    _selectedInterests.addAll(s.interests);
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    _customInterest.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= 6) return;
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (x == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dest = p.join(
      dir.path,
      'profile_${DateTime.now().millisecondsSinceEpoch}_${_photos.length}.jpg',
    );
    await File(x.path).copy(dest);
    setState(() => _photos.add(dest));
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final year = int.tryParse(_year.text.trim());
      if (year == null) throw StateError('Enter a valid birth year');
      final interests = [
        ..._selectedInterests,
        if (_customInterest.text.trim().isNotEmpty)
          _customInterest.text.trim(),
      ];
      await ref.read(sessionControllerProvider.notifier).saveProfile(
            displayName: _name.text,
            bio: _bio.text,
            gender: _gender,
            preference: _pref,
            birthYear: year,
            interests: interests,
            customInterest: _customInterest.text,
            photoPaths: _photos,
          );
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Bad state: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create your profile')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Photos (max 6) · verification status: pending until cloud review',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 96,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _photos.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(_photos[i]),
                                  width: 88,
                                  height: 88,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                child: IconButton(
                                  iconSize: 18,
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.black54,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () => setState(
                                    () => _photos.removeAt(i),
                                  ),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                        ),
                      if (_photos.length < 6)
                        InkWell(
                          onTap: _addPhoto,
                          child: Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.add_a_photo_outlined),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _bio,
                  maxLength: 500,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _year,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Birth year (18+)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _gender,
                  decoration: const InputDecoration(
                    labelText: 'Gender',
                    border: OutlineInputBorder(),
                  ),
                  items: _genders
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => _gender = v ?? _gender),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _prefs.contains(_pref) ? _pref : 'women',
                  decoration: const InputDecoration(
                    labelText: 'Interested in',
                    border: OutlineInputBorder(),
                  ),
                  items: _prefs
                      .map((g) => DropdownMenuItem(value: g, child: Text(g)))
                      .toList(),
                  onChanged: (v) => setState(() => _pref = v ?? _pref),
                ),
                const SizedBox(height: 16),
                const Text('Interests',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _interestPool.map((i) {
                    final on = _selectedInterests.contains(i);
                    return FilterChip(
                      label: Text(i),
                      selected: on,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _selectedInterests.add(i);
                          } else {
                            _selectedInterests.remove(i);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customInterest,
                  decoration: const InputDecoration(
                    labelText: 'Custom interest (free text)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      style: TextStyle(color: Colors.red.shade700)),
                ],
                const SizedBox(height: 24),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Save & enter In Range'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
