import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

class LocationSelectionResult {
  const LocationSelectionResult({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.address,
  });

  final double latitude;
  final double longitude;
  final String label;
  final String? address;
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({
    required this.isArabic,
    this.initialCenterLatitude,
    this.initialCenterLongitude,
    this.initialSelection,
    super.key,
  });

  final bool isArabic;
  final double? initialCenterLatitude;
  final double? initialCenterLongitude;
  final LocationSelectionResult? initialSelection;

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const LatLng _defaultCenter = LatLng(30.0444, 31.2357);

  final MapController _mapController = MapController();
  LatLng? _selectedPoint;
  String? _selectedLabel;
  String? _selectedAddress;
  bool _loadingAddress = false;
  bool _locatingCurrentPosition = false;
  int _addressRequestId = 0;

  @override
  void initState() {
    super.initState();
    final initialSelection = widget.initialSelection;
    if (initialSelection == null) {
      return;
    }
    _selectedPoint = LatLng(
      initialSelection.latitude,
      initialSelection.longitude,
    );
    _selectedLabel = initialSelection.label;
    _selectedAddress = initialSelection.address;
    if (_selectedLabel == null || _selectedLabel!.trim().isEmpty) {
      unawaited(_resolveSelectionDetails(_selectedPoint!));
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  LatLng get _initialCenter {
    if (widget.initialCenterLatitude != null &&
        widget.initialCenterLongitude != null) {
      return LatLng(
        widget.initialCenterLatitude!,
        widget.initialCenterLongitude!,
      );
    }
    final initialSelection = widget.initialSelection;
    if (initialSelection != null) {
      return LatLng(initialSelection.latitude, initialSelection.longitude);
    }
    return _defaultCenter;
  }

  double get _initialZoom {
    if (widget.initialSelection != null) {
      return 16;
    }
    if (widget.initialCenterLatitude != null &&
        widget.initialCenterLongitude != null) {
      return 14;
    }
    return 6;
  }

  String _tr({required String en, required String ar}) {
    return widget.isArabic ? ar : en;
  }

  void _showSnack(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _selectPoint(
    LatLng point, {
    String? label,
    String? address,
    bool resolveAddress = true,
    bool moveMap = false,
  }) {
    if (moveMap) {
      _mapController.move(point, 16);
    }
    setState(() {
      _selectedPoint = point;
      _selectedLabel = label;
      _selectedAddress = address;
      _loadingAddress = resolveAddress;
    });
    if (resolveAddress) {
      unawaited(_resolveSelectionDetails(point));
    }
  }

  Future<void> _resolveSelectionDetails(LatLng point) async {
    final requestId = ++_addressRequestId;
    try {
      await setLocaleIdentifier(widget.isArabic ? 'ar_EG' : 'en_US');
      final placemarks = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      if (!mounted || requestId != _addressRequestId) {
        return;
      }
      final details = _buildLocationDetails(placemarks);
      setState(() {
        _selectedLabel = details.$1;
        _selectedAddress = details.$2;
        _loadingAddress = false;
      });
    } catch (_) {
      if (!mounted || requestId != _addressRequestId) {
        return;
      }
      setState(() {
        _selectedLabel ??= _tr(en: 'Dropped pin', ar: 'النقطة المحددة');
        _loadingAddress = false;
      });
    }
  }

  (String, String?) _buildLocationDetails(List<Placemark> placemarks) {
    if (placemarks.isEmpty) {
      return (_tr(en: 'Dropped pin', ar: 'النقطة المحددة'), null);
    }

    final placemark = placemarks.first;
    final label =
        _firstNonEmpty([
          placemark.name,
          placemark.street,
          placemark.subLocality,
          placemark.locality,
          placemark.country,
        ]) ??
        _tr(en: 'Dropped pin', ar: 'النقطة المحددة');
    final addressParts = <String>[];
    for (final part in [
      placemark.street,
      placemark.subLocality,
      placemark.locality,
      placemark.administrativeArea,
      placemark.country,
    ]) {
      final normalized = part?.trim();
      if (normalized == null ||
          normalized.isEmpty ||
          addressParts.contains(normalized)) {
        continue;
      }
      addressParts.add(normalized);
    }
    return (label, addressParts.isEmpty ? null : addressParts.join(', '));
  }

  String? _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim();
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  Future<void> _useCurrentLocation() async {
    if (_locatingCurrentPosition) {
      return;
    }
    setState(() => _locatingCurrentPosition = true);
    try {
      final position = await _loadCurrentPosition();
      if (!mounted || position == null) {
        return;
      }
      _selectPoint(
        LatLng(position.latitude, position.longitude),
        label: _tr(en: 'Current location', ar: 'موقعي الحالي'),
        resolveAddress: true,
        moveMap: true,
      );
    } finally {
      if (mounted) {
        setState(() => _locatingCurrentPosition = false);
      }
    }
  }

  Future<Position?> _loadCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              _tr(en: 'Location services are off', ar: 'خدمات الموقع متوقفة'),
            ),
            content: Text(
              _tr(
                en: 'Turn on location services to use your current position.',
                ar: 'فعّل خدمات الموقع لاستخدام موقعك الحالي.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_tr(en: 'Cancel', ar: 'إلغاء')),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await Geolocator.openLocationSettings();
                },
                child: Text(_tr(en: 'Open settings', ar: 'فتح الإعدادات')),
              ),
            ],
          ),
        );
      }
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _showSnack(
        _tr(
          en: 'Location permission is required to use your current position',
          ar: 'صلاحية الموقع مطلوبة لاستخدام موقعك الحالي',
        ),
      );
      return null;
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              _tr(
                en: 'Location permission is blocked',
                ar: 'صلاحية الموقع محظورة',
              ),
            ),
            content: Text(
              _tr(
                en: 'Allow location access from app settings to use this option.',
                ar: 'اسمح بالوصول للموقع من إعدادات التطبيق لاستخدام هذا الخيار.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_tr(en: 'Cancel', ar: 'إلغاء')),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await Geolocator.openAppSettings();
                },
                child: Text(_tr(en: 'App settings', ar: 'إعدادات التطبيق')),
              ),
            ],
          ),
        );
      }
      return null;
    }

    try {
      return Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (_) {
      _showSnack(
        _tr(
          en: 'Failed to read your current location',
          ar: 'تعذر تحديد موقعك الحالي',
        ),
      );
      return null;
    }
  }

  void _confirmSelection() {
    final selectedPoint = _selectedPoint;
    if (selectedPoint == null) {
      return;
    }
    final label = _selectedLabel?.trim().isNotEmpty == true
        ? _selectedLabel!.trim()
        : _tr(en: 'Dropped pin', ar: 'النقطة المحددة');
    final address = _selectedAddress?.trim();
    Navigator.of(context).pop(
      LocationSelectionResult(
        latitude: selectedPoint.latitude,
        longitude: selectedPoint.longitude,
        label: label,
        address: address == null || address.isEmpty ? null : address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedPoint = _selectedPoint;
    final subtitle = selectedPoint == null
        ? _tr(
            en: 'Tap anywhere on the map to drop a pin.',
            ar: 'اضغط على أي مكان في الخريطة لتحديد نقطة.',
          )
        : _selectedAddress?.trim().isNotEmpty == true
        ? _selectedAddress!.trim()
        : _tr(en: 'Coordinates only', ar: 'إحداثيات فقط');
    final coordinates = selectedPoint == null
        ? null
        : '${selectedPoint.latitude.toStringAsFixed(5)}, '
              '${selectedPoint.longitude.toStringAsFixed(5)}';

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(en: 'Choose location', ar: 'اختيار الموقع')),
        actions: [
          TextButton(
            onPressed: selectedPoint == null ? null : _confirmSelection,
            child: Text(_tr(en: 'Send', ar: 'إرسال')),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: theme.colorScheme.surfaceContainerLowest,
            child: Text(
              _tr(
                en: 'Pick a place from the map or jump to your current location.',
                ar: 'اختر مكانًا من الخريطة أو انتقل إلى موقعك الحالي.',
              ),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _initialCenter,
                    initialZoom: _initialZoom,
                    onTap: (_, point) => _selectPoint(point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.chatify.app',
                      maxZoom: 19,
                    ),
                    if (selectedPoint != null)
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: selectedPoint,
                            width: 48,
                            height: 48,
                            child: Icon(
                              Icons.location_on,
                              size: 40,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          'OpenStreetMap contributors',
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://www.openstreetmap.org/copyright',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.small(
                    heroTag: 'location-picker-current-location',
                    onPressed: _useCurrentLocation,
                    child: _locatingCurrentPosition
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_outlined),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedPoint == null
                        ? _tr(
                            en: 'No location selected yet',
                            ar: 'لم يتم تحديد موقع بعد',
                          )
                        : _selectedLabel?.trim().isNotEmpty == true
                        ? _selectedLabel!.trim()
                        : _tr(en: 'Dropped pin', ar: 'النقطة المحددة'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_loadingAddress)
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _tr(
                              en: 'Loading address...',
                              ar: 'جارٍ تحميل العنوان...',
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Text(subtitle),
                  if (coordinates != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      coordinates,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: selectedPoint == null
                          ? null
                          : _confirmSelection,
                      icon: const Icon(Icons.send_outlined),
                      label: Text(_tr(en: 'Send location', ar: 'إرسال الموقع')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
