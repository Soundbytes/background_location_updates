/*
 *  Copyright 2018 Georg Grab
 *
 *  Licensed under the Apache License, Version 2.0 (the "License");
 *  you may not use this file except in compliance with the License.
 *  You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 *  Unless required by applicable law or agreed to in writing, software
 *  distributed under the License is distributed on an "AS IS" BASIS,
 *  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *  See the License for the specific language governing permissions and
 *  limitations under the License.
*/

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:json_annotation/json_annotation.dart';

part 'background_location_updates.g.dart';

/// Represents the PermissionState of Background Location on iOS,
/// and ACCESS_COARSE_LOCATION or ACCESS_FINE_LOCATION on Android.
enum PermissionState { 
  /// Indicates that the Permission was Granted.
  GRANTED, 

  /// Only on iOS: Indicates that the Permission was granted, but only
  /// while the Application is running, not while in the Background.
  PARTIAL, 

  /// Indicates that the Permission has been denied.
  DENIED 
}

PermissionState _toPermissionState(int nativeCode) {
  switch (nativeCode) {
    case 1:
      return PermissionState.GRANTED;
    case 2:
      return PermissionState.PARTIAL;
    case 3:
      return PermissionState.DENIED;
    default:
      throw 'Constructed invalid permissionState from native code: $nativeCode';
  }
}

class AndroidSpecificLocationData {
  /// The Course Accuracy, measured in degrees
  /// In the Android Documentation, this is referred to as 
  /// bearingAccuracy.
  double courseAccuracy;

  /// The Speed Accuracy, measured in m/s.
  double speedAccuracy;

  /// The Provider of this Location Trace
  String provider;

  AndroidSpecificLocationData({
    this.courseAccuracy,
    this.provider, 
    this.speedAccuracy
  });

  @override String toString() {
    return 'AndroidSpecific(cAcc=$courseAccuracy, provider=$provider, sAcc=$speedAccuracy)';
  }
}

class IOSSpecificLocationData {
  /// The Logical Floor of the User. See iOS Documentation.
  /// May be null.
  int logicalFloor;

  IOSSpecificLocationData({
    this.logicalFloor
  });

  @override String toString() {
    return 'IOSSpecific(floor=$logicalFloor)';
  }
}

@JsonSerializable()
class LocationTrace extends Object with _$LocationTraceSerializerMixin {
  /// The unique, monotonically increasing ID of this Trace.
  int id;

  /// The Latitude of the Device
  double latitude;

  /// The Longitude of the Device
  double longitude;

  /// The Altitude. Only available when the Location Source is GPS.
  double altitude;

  /// The current Device Speed
  double speed;

  /// How many times this trace has been read from the SQLite Database
  int readCount;

  /// The horizontal accuracy radius of this Trace, in meters.
  double accuracy;

  /// The vertical accuracy radius of this Trace, in meters.
  double verticalAccuracy;

  /// The Unix Epoch, in Milliseconds.
  int time;

  /// Where the device is currently heading, measured in degrees from north
  double course;

  /// The Android specific Location Data. `null` if on a iOS Device.
  AndroidSpecificLocationData androidSpecifics;

  /// The iOS specific Location Data. `null` if on an Android Device.
  IOSSpecificLocationData iosSpecifics;

  LocationTrace(
      {this.id,
      this.latitude,
      this.longitude,
      this.altitude,
      this.speed,
      this.readCount,
      this.time,
      this.course,
      this.androidSpecifics,
      this.iosSpecifics,
      this.verticalAccuracy,
      this.accuracy});

  static LocationTrace fromMap(Map<String, dynamic> map) {
    IOSSpecificLocationData iosSpecificLocationData;
    AndroidSpecificLocationData androidSpecificLocationData;

    if (Platform.isAndroid) {
      androidSpecificLocationData = AndroidSpecificLocationData(
        courseAccuracy: map["courseAccuracy"] as double,
        speedAccuracy: map["speedAccuracy"] as double,
        provider: map["provider"] as String
      );
    } else if (Platform.isIOS) {
      iosSpecificLocationData = IOSSpecificLocationData(
        logicalFloor: null
      );
    }

    final trace = LocationTrace(
        id: map["id"].toInt(),
        latitude: map["latitude"] as double,
        longitude: map["longitude"] as double,
        time: (map["time"] as double).toInt(),
        speed: (map["speed"] as double),
        readCount:  (map["readCount"] as double).toInt(),
        accuracy: map["accuracy"] as double,
        verticalAccuracy: map["verticalAccuracy"] as double,
        course: map["course"] as double,
        androidSpecifics: androidSpecificLocationData,
        iosSpecifics: iosSpecificLocationData,
    );
    if (map["altitude"] as double != 0.0) {
      trace.altitude = map["altitude"] as double;
    }
    return trace;
  }

  @override
  String toString() {
    return "LocationTrace(id=$id, lat=$latitude, lng=$longitude, acc=$accuracy, vAcc=$verticalAccuracy, speed=$speed, alt=$altitude, readCount=$readCount, time=$time, course=$course, ios=$iosSpecifics, android=$androidSpecifics)";
  }

  factory LocationTrace.fromJson(Map<String, dynamic> json) => _$LocationTraceFromJson(json);
}

abstract class Strategy {
  Future<bool> invoke(MethodChannel channel);
  Future<void> revert(MethodChannel channel);
}

abstract class AndroidStrategy extends Strategy {}

class AndroidPeriodicRequestStrategy extends AndroidStrategy {
  Duration requestInterval;
  AndroidPeriodicRequestStrategy({this.requestInterval});

  @override
  Future<bool> invoke(MethodChannel channel) async {
    final bool success = await channel.invokeMethod(
        'trackStart/android-strategy:periodic',
        [this.requestInterval.inMilliseconds]);
    return success;
  }

  @override
  Future<void> revert(MethodChannel channel) async {
    await channel.invokeMethod('trackStop/android-strategy:periodic', []);
  }
}

class AndroidBroadcastBasedRequestStrategy extends AndroidStrategy {
  Duration requestInterval;
  AndroidBroadcastBasedRequestStrategy({this.requestInterval});

  @override
  Future<bool> invoke(MethodChannel channel) async {
    final bool success = await channel.invokeMethod(
        'trackStart/android-strategy:broadcast',
        [this.requestInterval.inMilliseconds]);
    return success;
  }

  @override
  Future<void> revert(MethodChannel channel) async {
    await channel.invokeMethod('trackStop/android-strategy:broadcast', []);
  }
}

abstract class IOSStrategy extends Strategy {
  static const int ACCURACY_BEST = 1;
  static const int ACCURACY_KILOMETER = 2;
  static const int ACCURACY_HUNDRED_METERS = 3;
  static const int ACCURACY_THREE_KILOMETERS = 4;
  static const int ACCURACY_NEAREST_TEN_METERS = 5;
}

class IOSSignificantLocationChangeStrategy extends IOSStrategy {
  int desiredAccuracy;

  IOSSignificantLocationChangeStrategy(
      {this.desiredAccuracy = IOSStrategy.ACCURACY_HUNDRED_METERS});
  @override
  Future<bool> invoke(MethodChannel channel) async {
    final bool success = await channel.invokeMethod(
        'trackStart/ios-strategy:significant-location-change',
        [desiredAccuracy]);
    return success;
  }

  @override
  Future<void> revert(MethodChannel channel) async {
    await channel
        .invokeMethod('trackStop/ios-strategy:significant-location-change', []);
  }
}

class IOSLocationChangeStrategy extends IOSStrategy {
  int desiredAccuracy;

  IOSLocationChangeStrategy(
      {this.desiredAccuracy = IOSStrategy.ACCURACY_HUNDRED_METERS});

  @override
  Future<bool> invoke(MethodChannel channel) async {
    final bool success = await channel.invokeMethod(
        'trackStart/ios-strategy:location-change', [desiredAccuracy]);
    return success;
  }

  @override
  Future<void> revert(MethodChannel channel) async {
    await channel.invokeMethod('trackStop/ios-strategy:location-change', []);
  }
}

/**
 * Retrieve periodic location updates, even when the main App is not running. 
 * Useful for Navigation Apps to keep a rough idea of where the User is heading, and various other purposes. 
 * Please don't be evil though, and tell the User exactly how, when and why you wish to retrieve her location. 
 * Before integrating this Plugin in your app, please read [this](https://www.dataprotection.ie/docs/Guidance-Note-for-Data-Controllers-on-Location-Data/1587.htm).
 */
class BackgroundLocationUpdates {
  static Strategy _lastStrategy;
  static const MethodChannel _channel =
      const MethodChannel('plugins.gjg.io/background_location_updates');

  static const EventChannel _trackingStateChangeEvents = const EventChannel(
      'plugins.gjg.io/background_location_updates/tracking_state');

  static const EventChannel _permissionStateChangeEvents = const EventChannel(
      'plugins.gjg.io/background_location_updates/permission_state');

  /// Starts the Location Tracking using the specified strategies.
  static Future<void> startTrackingLocation(
      {AndroidStrategy androidStrategy, IOSStrategy iOSStrategy}) async {
    if (Platform.isAndroid) {
      BackgroundLocationUpdates._lastStrategy = androidStrategy;
      await androidStrategy.invoke(_channel);
    } else if (Platform.isIOS) {
      BackgroundLocationUpdates._lastStrategy = iOSStrategy;
      await iOSStrategy.invoke(_channel);
    }
  }

  /// Returns a [Stream] of [bool] indicating whether the Location Tracking is active.
  static Stream<bool> streamLocationActive() {
    return _trackingStateChangeEvents.receiveBroadcastStream().cast<bool>();
  }

  /// Stops the Location Tracking.
  static Future<bool> stopTrackingLocation() async {
    if (BackgroundLocationUpdates._lastStrategy == null) {
      await _channel.invokeMethod('revertActiveStrategy', []);
      return true;
    } else {
      await BackgroundLocationUpdates._lastStrategy.revert(_channel);
      return true;
    }
  }

  /// Tries requesting the permission for tracking the User in the Background.
  /// 
  ///  Returns a [PermissionState] indicating
  /// if a dialogBox requesting the permission has been shown to the User.
  static Future<PermissionState> requestPermission() async {
    if (await getPermissionState().first == PermissionState.GRANTED) {
      return PermissionState.GRANTED;
    }
    await _channel.invokeMethod('requestPermission');
    return getPermissionState().take(2).last;
  }

  /// Gets a Stream representing the Permission State of the Background Tracking.
  /// 
  /// Returns a [Stream] of [PermissionState]s, indicating Permission State changes as they occur.
  static Stream<PermissionState> getPermissionState() {
    return _permissionStateChangeEvents
        .receiveBroadcastStream()
        .cast<int>()
        .map(_toPermissionState);
  }

  /// Gets all Location Traces, regardless if they have been marked as read or not.
  /// 
  /// Returns a Future of [List<LocationTrace>]
  static Future<List<LocationTrace>> getLocationTraces() async {
    List<dynamic> traces = await _channel.invokeMethod('getLocationTraces');
    return traces
        .cast<Map<dynamic, dynamic>>()
        .map((trace) => trace.cast<String, double>())
        .map(LocationTrace.fromMap)
        .toList();
  }

  /// Gets only the Location Traces that have not been marked as read previously
  /// 
  /// Returns a Future of [List<LocationTrace>]
  static Future<List<LocationTrace>> getUnreadLocationTraces() async {
    List<dynamic> traces =
        await _channel.invokeMethod('getUnreadLocationTraces');
    return traces
        .cast<Map>()
        .map((trace) => trace.cast<String, dynamic>())
        .map(LocationTrace.fromMap)
        .toList();
  }

  /// Gets the internal SQLite Database Path. Can be used in conjunction with other extensions
  /// such as SQFlite.
  /// 
  /// Returns a [Future<String>], denoting the absolute path of the SQLite Database.
  static Future<String> getSqliteDatabasePath() async {
    final String path = await _channel.invokeMethod('getSqliteDatabasePath');
    return path;
  }

  /// Gets the count of Unread Location Traces.
  /// 
  /// Returns a [Future<int>].
  static Future<int> getUnreadLocationTracesCount() async {
    final int count =
        await _channel.invokeMethod('getUnreadLocationTracesCount');
    return count;
  }

  /// Gets the count of all Location Traces.
  /// 
  /// Returns a [Future<int>].
  static Future<int> getLocationTracesCount() async {
    final int count = await _channel.invokeMethod('getLocationTracesCount');
    return count;
  }

  /// Marks a list of [ids] as read. The [ids] may be retrieved from a List of [LocationTrace]
  /// like this:
  /// 
  /// ```dart
  /// await BackgroundLocationUpdates.markAsRead(
  ///     traces.map((trace) => trace.id).asList()
  /// );
  /// ```
  /// 
  /// Returns a [Future<void>], indicating when the operation is complete.
  static Future<void> markAsRead(List<int> ids) async {
    await _channel.invokeMethod('markAsRead', [ids]);
  }
}
