import 'package:flutter/material.dart';

import '../auth/auth_status_banner.dart';
import '../constants/app_colors.dart';
import '../constants/app_widgets.dart';
import '../core/models/orbitcare_models.dart';
import '../core/services/orbitcare_api_client.dart';
import '../core/state/session_controller.dart';
import '../routes/app_routes.dart';

class AddMeasurementScreen extends StatefulWidget {
  final OrbitCareApiClient? apiClient;
  final String? authToken;

  const AddMeasurementScreen({
    super.key,
    this.apiClient,
    this.authToken,
  });

  @override
  State<AddMeasurementScreen> createState() => _AddMeasurementScreenState();
}

class _AddMeasurementScreenState extends State<AddMeasurementScreen> {
  final _heartRateController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _respRateController = TextEditingController();
  final _tempController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _bloodSugarController = TextEditingController();
  final _sleepMinutesController = TextEditingController();
  final _stepsController = TextEditingController();

  String? _sleepQuality;
  String? _activityLevel;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _heartRateController.dispose();
    _spo2Controller.dispose();
    _respRateController.dispose();
    _tempController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _bloodSugarController.dispose();
    _sleepMinutesController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  double? _parseOptionalDouble(
    TextEditingController controller, {
    required String label,
    required double min,
    required double max,
    required List<String> errors,
  }) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    final val = double.tryParse(text);
    if (val == null || val < min || val > max) {
      errors.add('$label must be a number between $min and $max.');
      return null;
    }
    return val;
  }

  Future<void> _submit() async {
    final errors = <String>[];

    final heartRate = _parseOptionalDouble(
      _heartRateController,
      label: 'Heart Rate',
      min: 20,
      max: 260,
      errors: errors,
    );
    final spo2 = _parseOptionalDouble(
      _spo2Controller,
      label: 'SpO2',
      min: 0,
      max: 100,
      errors: errors,
    );
    final respRate = _parseOptionalDouble(
      _respRateController,
      label: 'Respiratory Rate',
      min: 4,
      max: 80,
      errors: errors,
    );
    final temp = _parseOptionalDouble(
      _tempController,
      label: 'Temperature',
      min: 30,
      max: 45,
      errors: errors,
    );
    final systolic = _parseOptionalDouble(
      _systolicController,
      label: 'Systolic BP',
      min: 40,
      max: 260,
      errors: errors,
    );
    final diastolic = _parseOptionalDouble(
      _diastolicController,
      label: 'Diastolic BP',
      min: 20,
      max: 180,
      errors: errors,
    );
    final bloodSugar = _parseOptionalDouble(
      _bloodSugarController,
      label: 'Blood Sugar',
      min: 10,
      max: 800,
      errors: errors,
    );
    final sleepMinutes = _parseOptionalDouble(
      _sleepMinutesController,
      label: 'Sleep Duration',
      min: 0,
      max: 1440,
      errors: errors,
    );
    final steps = _parseOptionalDouble(
      _stepsController,
      label: 'Steps',
      min: 0,
      max: 200000,
      errors: errors,
    );

    if (systolic != null && diastolic != null && systolic < diastolic) {
      errors.add('Systolic BP must be greater than or equal to Diastolic BP.');
    }

    if (errors.isNotEmpty) {
      setState(() {
        _errorMessage = errors.first;
      });
      return;
    }

    final payload = <String, dynamic>{
      'source': 'manual',
    };
    if (heartRate != null) {
      payload['heartRate'] = heartRate;
      payload['pulseRate'] = heartRate;
    }
    if (spo2 != null) payload['spo2'] = spo2;
    if (respRate != null) payload['respiratoryRate'] = respRate;
    if (temp != null) payload['temperature'] = temp;
    if (bloodSugar != null) payload['bloodSugar'] = bloodSugar;

    if (systolic != null || diastolic != null) {
      payload['bloodPressure'] = <String, dynamic>{
        if (systolic != null) 'systolic': systolic,
        if (diastolic != null) 'diastolic': diastolic,
      };
    }

    if (sleepMinutes != null || _sleepQuality != null) {
      payload['sleep'] = <String, dynamic>{
        if (sleepMinutes != null) 'durationMinutes': sleepMinutes.round(),
        if (_sleepQuality != null) 'quality': _sleepQuality,
      };
    }

    if (steps != null || _activityLevel != null) {
      payload['activity'] = <String, dynamic>{
        if (steps != null) 'steps': steps.round(),
        if (_activityLevel != null) 'level': _activityLevel,
      };
    }

    if (payload.length <= 1) {
      setState(() {
        _errorMessage = 'Enter at least one health measurement before saving.';
      });
      return;
    }

    final sessionController = SessionScope.maybeOf(context);
    final apiClient = widget.apiClient ?? sessionController?.apiClient;
    final token = widget.authToken ?? sessionController?.token;

    if (apiClient == null || token == null || token.isEmpty) {
      setState(() {
        _errorMessage = 'You must be signed in to record a measurement.';
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await apiClient.createMeasurement(token: token, payload: payload);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on OrbitCareApiException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized && sessionController != null) {
        await sessionController.handleUnauthorized();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.login,
          (_) => false,
        );
        return;
      }
      setState(() {
        _errorMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Unable to save measurement. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Log Health Measurement',
          style: TextStyle(
            color: AppColors.navy,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.navy),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter one or more vital signs below. Values are saved to your authenticated OrbitCare record.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: AppColors.grey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null) ...[
                AuthStatusBanner(isError: true, message: _errorMessage!),
                const SizedBox(height: 16),
              ],
              _MeasurementSectionCard(
                title: 'Cardiopulmonary Vitals',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_heart_rate'),
                          controller: _heartRateController,
                          label: 'Heart Rate',
                          suffix: 'bpm',
                          hint: '72',
                          enabled: !_isSubmitting,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_spo2'),
                          controller: _spo2Controller,
                          label: 'SpO2',
                          suffix: '%',
                          hint: '98',
                          enabled: !_isSubmitting,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_resp_rate'),
                          controller: _respRateController,
                          label: 'Resp. Rate',
                          suffix: 'br/min',
                          hint: '15',
                          enabled: !_isSubmitting,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_temperature'),
                          controller: _tempController,
                          label: 'Temperature',
                          suffix: '°C',
                          hint: '36.8',
                          enabled: !_isSubmitting,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MeasurementSectionCard(
                title: 'Blood Pressure & Glucose',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_systolic'),
                          controller: _systolicController,
                          label: 'Systolic',
                          suffix: 'mmHg',
                          hint: '120',
                          enabled: !_isSubmitting,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_diastolic'),
                          controller: _diastolicController,
                          label: 'Diastolic',
                          suffix: 'mmHg',
                          hint: '78',
                          enabled: !_isSubmitting,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _NumericInputField(
                    key: const Key('input_blood_sugar'),
                    controller: _bloodSugarController,
                    label: 'Blood Sugar',
                    suffix: 'mg/dL',
                    hint: '95',
                    enabled: !_isSubmitting,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _MeasurementSectionCard(
                title: 'Sleep & Activity (Optional)',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_sleep_minutes'),
                          controller: _sleepMinutesController,
                          label: 'Sleep Duration',
                          suffix: 'min',
                          hint: '420',
                          enabled: !_isSubmitting,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _sleepQuality,
                          decoration: _dropdownDecoration('Sleep Quality'),
                          items: const [
                            DropdownMenuItem(value: 'poor', child: Text('Poor')),
                            DropdownMenuItem(value: 'fair', child: Text('Fair')),
                            DropdownMenuItem(value: 'good', child: Text('Good')),
                            DropdownMenuItem(
                              value: 'excellent',
                              child: Text('Excellent'),
                            ),
                          ],
                          onChanged: _isSubmitting
                              ? null
                              : (val) => setState(() => _sleepQuality = val),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _NumericInputField(
                          key: const Key('input_steps'),
                          controller: _stepsController,
                          label: 'Steps',
                          suffix: 'steps',
                          hint: '6500',
                          enabled: !_isSubmitting,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _activityLevel,
                          decoration: _dropdownDecoration('Activity Level'),
                          items: const [
                            DropdownMenuItem(value: 'low', child: Text('Low')),
                            DropdownMenuItem(
                                value: 'light', child: Text('Light')),
                            DropdownMenuItem(
                              value: 'moderate',
                              child: Text('Moderate'),
                            ),
                            DropdownMenuItem(value: 'high', child: Text('High')),
                            DropdownMenuItem(
                              value: 'intense',
                              child: Text('Intense'),
                            ),
                          ],
                          onChanged: _isSubmitting
                              ? null
                              : (val) => setState(() => _activityLevel = val),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                text: 'Save Measurement',
                icon: Icons.check,
                isLoading: _isSubmitting,
                onPressed: _isSubmitting ? null : _submit,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _dropdownDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 13, color: AppColors.navy),
      filled: true,
      fillColor: AppColors.lightBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    );
  }
}

class _MeasurementSectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _MeasurementSectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _NumericInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String suffix;
  final String hint;
  final bool enabled;

  const _NumericInputField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    required this.hint,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14.5, color: AppColors.navy),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        labelStyle: const TextStyle(fontSize: 13, color: AppColors.navy),
        suffixStyle: const TextStyle(
          fontSize: 12,
          color: AppColors.grey,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: AppColors.lightBackground,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }
}
