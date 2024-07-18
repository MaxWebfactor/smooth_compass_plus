import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:location/location.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:smooth_compass_plus/utils/src/qibla_utils.dart';

import '../smooth_compass_plus.dart';
import 'widgets/error_widget.dart';

double preValue = 0;
double turns = 0;

///custom callback for building widget
typedef WidgetBuilder = Widget Function(BuildContext context,
    AsyncSnapshot<CompassModel>? compassData, Widget compassAsset);

class SmoothCompassWidget extends StatefulWidget {
  final WidgetBuilder? compassBuilder;
  final Widget? compassAsset;
  final Widget? loadingAnimation;
  final int? rotationSpeed;
  final double? height;
  final double? width;
  final bool? isQiblahCompass;
  final Widget? errorLocationServiceWidget;
  final Widget? errorLocationPermissionWidget;
  final bool forceGPS;

  const SmoothCompassWidget({
    Key? key,
    this.compassBuilder,
    this.compassAsset,
    this.rotationSpeed = 400,
    this.height = 200,
    this.width = 200,
    this.isQiblahCompass = false,
    this.errorLocationServiceWidget,
    this.errorLocationPermissionWidget,
    this.loadingAnimation,
    this.forceGPS = false,
  }) : super(key: key);

  @override
  State<SmoothCompassWidget> createState() => _SmoothCompassWidgetState();
}

class _SmoothCompassWidgetState extends State<SmoothCompassWidget> {
  var location = Location();
  Stream<CompassModel>? _compassStream;
  double currentHeading = 0.0;
  double qiblahOffset = 0.0;
  double previousHeading = 0.0;
  @override
  void initState() {
    super.initState();
    if (widget.forceGPS && widget.isQiblahCompass!) {
      _initializeCompassStream();
    }
    // _initializeCompassStream();
  }

  void _initializeCompassStream() {
    if (widget.forceGPS) {
      _getLocation().then((locationData) {
        if (locationData != null) {
          qiblahOffset = _calculateQiblahOffset(
            locationData.latitude ?? 0,
            locationData.longitude ?? 0,
          );
          if (mounted) {
            setState(() {
              _compassStream = Stream.periodic(
                const Duration(milliseconds: 100),
                (_) {
                  return CompassModel(
                    turns: currentHeading / 360,
                    angle: currentHeading * -1,
                    qiblahOffset: qiblahOffset,
                    source: 'GPS',
                  );
                },
              );
            });
          }
          magnetometerEventStream().listen((MagnetometerEvent event) {
            double newHeading = atan2(event.y, event.x) * (180 / pi);
            // if (newHeading < 0) newHeading += 360;
            if (mounted)
              setState(() {
                currentHeading = newHeading;
                previousHeading = currentHeading;
              });
          });
        }
      });
    } else {
      Compass().isCompassAvailable().then((isAvailable) {
        if (isAvailable) {
          setState(() {
            _compassStream = Compass().compassUpdates(
              interval: const Duration(milliseconds: 200),
              azimuthFix: 0.0,
            );
          });
        } else {
          _getLocation().then((locationData) {
            if (locationData != null) {
              qiblahOffset = _calculateQiblahOffset(
                locationData.latitude ?? 0,
                locationData.longitude ?? 0,
              );
              setState(() {
                _compassStream = Stream.periodic(
                  const Duration(milliseconds: 200),
                  (_) {
                    return CompassModel(
                      turns: currentHeading / 360,
                      angle: currentHeading * -1,
                      qiblahOffset: qiblahOffset,
                      source: 'GPS',
                    );
                  },
                );
              });
              magnetometerEventStream().listen((MagnetometerEvent event) {
                double newHeading = atan2(event.y, event.x) * (180 / pi);
                // if (newHeading < 0) newHeading += 360;
                setState(() {
                  currentHeading = newHeading;
                  previousHeading = currentHeading;
                });
              });
            }
          });
        }
      });
    }
  }

  Future<bool> _checkLocationServiceAndPermissions() async {
    bool serviceEnabled = await location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await location.requestService();
      if (!serviceEnabled) {
        return false;
      }
    }

    PermissionStatus permissionGranted = await location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return false;
      }
    }
    return true;
  }

  Future<LocationData?> _getLocation() async {
    bool hasPermission = await _checkLocationServiceAndPermissions();
    if (!hasPermission) {
      return null;
    }

    LocationData locationData;
    try {
      locationData = await location.getLocation();
    } catch (e) {
      return null;
    }
    return locationData;
  }

  double _calculateQiblahOffset(double latitude, double longitude) {
    return Utils.getOffsetFromNorth(latitude, longitude);
  }

  @override
  Widget build(BuildContext context) {
    /// check if the compass support available
    return widget.forceGPS && widget.isQiblahCompass!
        ? StreamBuilder<CompassModel>(
            stream: _compassStream,
            builder: (context, AsyncSnapshot<CompassModel> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting ||
                  !snapshot.hasData) {
                return widget.loadingAnimation != null
                    ? widget.loadingAnimation!
                    : const Center(
                        child: CircularProgressIndicator(),
                      );
              }
              if (snapshot.hasError) {
                return widget.loadingAnimation != null
                    ? widget.loadingAnimation!
                    : const Center(
                        child: CircularProgressIndicator(),
                      );
              }
              return widget.compassBuilder == null
                  ? _defaultWidget(snapshot, context)
                  : widget.compassBuilder!(
                      context, snapshot, widget.compassAsset ?? Container());
            },
          )
        : FutureBuilder(
            future: Compass().isCompassAvailable(),
            builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return widget.loadingAnimation != null
                    ? widget.loadingAnimation!
                    : const Center(
                        child: CircularProgressIndicator(),
                      );
              }
              if (!snapshot.data! && widget.isQiblahCompass!) {
                /// Handle GPS
                return StreamBuilder<CompassModel>(
                  stream: _compassStream,
                  builder: (context, AsyncSnapshot<CompassModel> snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting ||
                        !snapshot.hasData) {
                      return widget.loadingAnimation != null
                          ? widget.loadingAnimation!
                          : const Center(
                              child: CircularProgressIndicator(),
                            );
                    }
                    if (snapshot.hasError) {
                      return widget.loadingAnimation != null
                          ? widget.loadingAnimation!
                          : const Center(
                              child: CircularProgressIndicator(),
                            );
                    }
                    return widget.compassBuilder == null
                        ? _defaultWidget(snapshot, context)
                        : widget.compassBuilder!(context, snapshot,
                            widget.compassAsset ?? Container());
                  },
                );
              }

              /// start compass stream
              return widget.isQiblahCompass!
                  ? FutureBuilder<bool>(
                      future: location.serviceEnabled(),
                      builder: (context, AsyncSnapshot<bool> serviceSnapshot) {
                        if (serviceSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return widget.loadingAnimation ??
                              const Center(
                                child: CircularProgressIndicator(),
                              );
                        } else if (serviceSnapshot.data == false) {
                          return widget.errorLocationServiceWidget ??
                              CustomErrorWidget(
                                title: "Enable Location",
                                onTap: () async {
                                  await location.requestService();
                                  setState(() {});
                                },
                                errMsg: 'Location service is disabled',
                              );
                        }

                        /// to Check Location permission if denied
                        return FutureBuilder<PermissionStatus>(
                            future: location.hasPermission(),
                            builder: (context,
                                AsyncSnapshot<PermissionStatus>
                                    permissionSnapshot) {
                              if (permissionSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return widget.loadingAnimation ??
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    );
                              } else if ((permissionSnapshot.data!) ==
                                  PermissionStatus.denied) {
                                return widget.errorLocationPermissionWidget ??
                                    CustomErrorWidget(
                                        errMsg:
                                            "Please allow location permissions to get the qiblah direction for current location",
                                        title: "Allow Permissions",
                                        onTap: () async {
                                          var status = await location
                                              .requestPermission();

                                          if (status ==
                                                  PermissionStatus.granted ||
                                              status ==
                                                  PermissionStatus
                                                      .grantedLimited) {
                                            setState(() {});
                                          }
                                        });
                              } else if ((permissionSnapshot.data ??
                                      PermissionStatus.deniedForever) ==
                                  PermissionStatus.deniedForever) {
                                return Platform.isAndroid
                                    ? widget.errorLocationPermissionWidget ??
                                        CustomErrorWidget(
                                            onTap: () async {
                                              await location
                                                  .requestPermission();
                                            },
                                            title: "Open Settings",
                                            errMsg:
                                                "Location is permanently denied")
                                    : const Padding(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 10),
                                        child: Center(
                                          child: Text(
                                              "please enable location permission from settings"),
                                        ),
                                      );
                              }
                              return FutureBuilder<LocationData?>(
                                  future: location.getLocation(),
                                  builder: (context,
                                      AsyncSnapshot<LocationData?>
                                          positionSnapshot) {
                                    if (positionSnapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return widget.loadingAnimation ??
                                          const Center(
                                            child: CircularProgressIndicator(),
                                          );
                                    } else {
                                      return StreamBuilder<CompassModel>(
                                        stream: Compass().compassUpdates(
                                            interval: const Duration(
                                              milliseconds: 200,
                                            ),
                                            azimuthFix: 0.0,
                                            currentLoc: MyLoc(
                                                latitude: positionSnapshot
                                                        .data?.latitude ??
                                                    0,
                                                longitude: positionSnapshot
                                                        .data?.longitude ??
                                                    0)),
                                        builder: (context,
                                            AsyncSnapshot<CompassModel>
                                                snapshot) {
                                          if (widget.compassAsset == null) {
                                            if (snapshot.connectionState ==
                                                ConnectionState.waiting) {
                                              return widget.loadingAnimation ??
                                                  const Center(
                                                    child:
                                                        CircularProgressIndicator(),
                                                  );
                                            }
                                            if (snapshot.hasError) {
                                              return Text(
                                                  snapshot.error.toString());
                                            }
                                            return widget.compassBuilder == null
                                                ? _defaultWidget(
                                                    snapshot, context)
                                                : widget.compassBuilder!(
                                                    context,
                                                    snapshot,
                                                    _defaultWidget(
                                                        snapshot, context));
                                          } else {
                                            if (snapshot.connectionState ==
                                                ConnectionState.waiting) {
                                              return widget.loadingAnimation ??
                                                  const Center(
                                                    child:
                                                        CircularProgressIndicator(),
                                                  );
                                            }
                                            if (snapshot.hasError) {
                                              return Text(
                                                  snapshot.error.toString());
                                            }
                                            return widget.compassBuilder == null
                                                ? AnimatedRotation(
                                                    turns:
                                                        snapshot.data!.turns *
                                                            -1,
                                                    duration: Duration(
                                                        milliseconds: widget
                                                            .rotationSpeed!),
                                                    child: widget.compassAsset!,
                                                  )
                                                : widget.compassBuilder!(
                                                    context,
                                                    snapshot,
                                                    AnimatedRotation(
                                                      turns:
                                                          snapshot.data!.turns *
                                                              -1,
                                                      duration: Duration(
                                                          milliseconds: widget
                                                              .rotationSpeed!),
                                                      child:
                                                          widget.compassAsset!,
                                                    ),
                                                  );
                                          }
                                        },
                                      );
                                    }
                                  });
                            });
                      })
                  : StreamBuilder<CompassModel>(
                      stream: Compass().compassUpdates(
                          interval: const Duration(
                            milliseconds: 200,
                          ),
                          azimuthFix: 0.0,
                          currentLoc: MyLoc(latitude: 0, longitude: 0)),
                      builder: (context, AsyncSnapshot<CompassModel> snapshot) {
                        if (widget.compassAsset == null) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return widget.loadingAnimation ??
                                const Center(
                                  child: CircularProgressIndicator(),
                                );
                          }
                          if (snapshot.hasError) {
                            return Text(snapshot.error.toString());
                          }
                          return widget.compassBuilder == null
                              ? _defaultWidget(snapshot, context)
                              : widget.compassBuilder!(context, snapshot,
                                  _defaultWidget(snapshot, context));
                        } else {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return widget.loadingAnimation ??
                                const Center(
                                  child: CircularProgressIndicator(),
                                );
                          }
                          if (snapshot.hasError) {
                            return Text(snapshot.error.toString());
                          }
                          return widget.compassBuilder == null
                              ? AnimatedRotation(
                                  turns: snapshot.data!.turns * -1,
                                  duration: Duration(
                                      milliseconds: widget.rotationSpeed!),
                                  child: widget.compassAsset!,
                                )
                              : widget.compassBuilder!(
                                  context,
                                  snapshot,
                                  AnimatedRotation(
                                    turns: snapshot.data!.turns * -1,
                                    duration: Duration(
                                        milliseconds: widget.rotationSpeed!),
                                    child: widget.compassAsset!,
                                  ),
                                );
                        }
                      },
                    );
            });
  }

  ///default widget if custom widget isn't provided
  Widget _defaultWidget(
      AsyncSnapshot<CompassModel> snapshot, BuildContext context) {
    return AnimatedRotation(
      turns: snapshot.data!.turns,
      duration: Duration(milliseconds: widget.rotationSpeed!),
      child: Container(
        height: widget.height ?? MediaQuery.of(context).size.shortestSide * 0.8,
        width: widget.width ?? MediaQuery.of(context).size.shortestSide * 0.8,
        decoration: const BoxDecoration(
            image: DecorationImage(
                image: AssetImage('assets/images/compass.png'),
                fit: BoxFit.cover)),
      ),
    );
  }
}

///calculating compass Model
getCompassValues(
    double heading, double latitude, double longitude, String source) {
  double direction = heading;
  direction = direction < 0 ? (360 + direction) : direction;

  double diff = direction - preValue;
  if (diff.abs() > 180) {
    if (preValue > direction) {
      diff = 360 - (direction - preValue).abs();
    } else {
      diff = (360 - (preValue - direction).abs()).toDouble();
      diff = diff * -1;
    }
  }

  turns += (diff / 360);
  preValue = direction;

  return CompassModel(
      turns: -1 * turns,
      angle: heading,
      qiblahOffset: getQiblaDirection(latitude, longitude, heading),
      source: source);
}

/// model to store the sensor value
class CompassModel {
  double turns;
  double angle;
  double qiblahOffset;
  String source;

  CompassModel(
      {required this.turns,
      required this.angle,
      required this.qiblahOffset,
      required this.source});
}
