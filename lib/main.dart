import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Civic Issue Reporting',
      theme: ThemeData(
        primarySwatch: Colors.red,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const IssueReportingScreen(),
    );
  }
}

class IssueReportingScreen extends StatefulWidget {
  const IssueReportingScreen({Key? key}) : super(key: key);

  @override
  State<IssueReportingScreen> createState() => _IssueReportingScreenState();
}

class _IssueReportingScreenState extends State<IssueReportingScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  File? _image;
  LatLng? _pickedLocation;
  bool _isSubmitting = false;

  final ImagePicker _picker = ImagePicker();

  Future<void> _pickImage() async {
    try {
      final pickedFile = await _picker.pickImage(source: ImageSource.camera);
      if (pickedFile != null) {
        setState(() {
          _image = File(pickedFile.path);
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _pickLocation() async {
    try {
      Location location = Location();
      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location services are disabled.')),
          );
          return;
        }
      }

      PermissionStatus permissionGranted = await location.hasPermission();
      if (permissionGranted == PermissionStatus.denied) {
        permissionGranted = await location.requestPermission();
        if (permissionGranted != PermissionStatus.granted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
          return;
        }
      }

      final locData = await location.getLocation();
      setState(() {
        _pickedLocation = LatLng(locData.latitude!, locData.longitude!);
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error getting location: $e')),
      );
    }
  }

  Future<String?> _uploadImage(File imageFile) async {
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('issue_images')
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');
      final uploadTask = storageRef.putFile(imageFile);
      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image upload failed: $e')),
      );
      return null;
    }
  }

  Future<void> _submitIssue() async {
    if (!_formKey.currentState!.validate()) return;
    if (_image == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a photo of the issue.')),
      );
      return;
    }
    if (_pickedLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick the location of the issue.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    final imageUrl = await _uploadImage(_image!);
    if (imageUrl == null) {
      setState(() => _isSubmitting = false);
      return;
    }

    await FirebaseFirestore.instance.collection('issues').add({
      'title': _titleController.text,
      'description': _descController.text,
      'imageUrl': imageUrl,
      'latitude': _pickedLocation!.latitude,
      'longitude': _pickedLocation!.longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });

    setState(() {
      _isSubmitting = false;
      _titleController.clear();
      _descController.clear();
      _image = null;
      _pickedLocation = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Issue submitted successfully!')),
    );
  }

  void _navigateToIssueList() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const IssueListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Report an Issue'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            tooltip: 'View Reported Issues',
            onPressed: _navigateToIssueList,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  prefixIcon: Icon(Icons.title),
                  border: OutlineInputBorder(),
                ),
                validator: (value) =>
                    value == null || value.isEmpty ? 'Enter a title' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  prefixIcon: Icon(Icons.description),
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
                validator: (value) => value == null || value.isEmpty
                    ? 'Enter a description'
                    : null,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.camera_alt),
                label: const Text('Add Photo'),
                onPressed: _pickImage,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_image != null) ...[
                const SizedBox(height: 8),
                Image.file(
                  _image!,
                  height: 150,
                  fit: BoxFit.cover,
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.location_on),
                label: const Text('Pick Location'),
                onPressed: _pickLocation,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              if (_pickedLocation != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Location: ${_pickedLocation!.latitude.toStringAsFixed(5)}, ${_pickedLocation!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 24),
              _isSubmitting
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _submitIssue,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Submit Issue',
                            style: TextStyle(fontSize: 18)),
                      ),
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class IssueListScreen extends StatelessWidget {
  const IssueListScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reported Issues')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('issues')
            .orderBy('timestamp', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('No issues reported yet.'));
          }

          final issues = snapshot.data!.docs;

          return RefreshIndicator(
            onRefresh: () async {
              await Future.delayed(const Duration(seconds: 1));
            },
            child: ListView.builder(
              itemCount: issues.length,
              itemBuilder: (context, index) {
                final issue = issues[index];
                final data = issue.data() as Map<String, dynamic>;

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: data['imageUrl'] != null
                        ? Image.network(
                            data['imageUrl'],
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.report_problem, size: 40),
                    title: Text(data['title'] ?? 'No Title'),
                    subtitle: Text(data['description'] ?? 'No Description'),
                    trailing: IconButton(
                      icon: const Icon(Icons.map),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => IssueMapScreen(
                                  latitude: data['latitude'],
                                  longitude: data['longitude'],
                                  title: data['title'],
                                )));
                      },
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class IssueMapScreen extends StatelessWidget {
  final double latitude;
  final double longitude;
  final String title;

  const IssueMapScreen({
    Key? key,
    required this.latitude,
    required this.longitude,
    required this.title,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final LatLng position = LatLng(latitude, longitude);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(target: position, zoom: 15),
        markers: {
          Marker(markerId: const MarkerId('issueLocation'), position: position),
        },
      ),
    );
  }
}
