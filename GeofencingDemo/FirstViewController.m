//
//  FirstViewController.m
//  GeofencingDemo
//
//  Created by Aaron Parecki on 3/1/16.
//  Copyright © 2016 Aaron Parecki. All rights reserved.
//

#import "FirstViewController.h"
#import <ArcGIS/ArcGIS.h>

#define kFeatureServiceURL @"http://services.arcgis.com/rOo16HdIMeOBI4Mb/ArcGIS/rest/services/Sample_Triggers/FeatureServer"

@interface FirstViewController ()

@property (nonatomic, strong) AGSGDBGeodatabase *geodatabase;
@property (nonatomic, strong) AGSGDBSyncTask *gdbTask;
@property (nonatomic, strong) CLLocationManager *locationManager;

@end

@implementation FirstViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Request authorization to monitor the phone's location from the user
    [self.locationManager requestAlwaysAuthorization];

    // Request permission to send notifications
    UIUserNotificationSettings *mySettings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert
                                                                               categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];

    // Create the Geodatabase Task referencing the feature service URL
    self.gdbTask = [[AGSGDBSyncTask alloc] initWithURL:[NSURL URLWithString:kFeatureServiceURL]];

    self.gdbTask.loadCompletion = ^(NSError* error){
        NSLog(@"Loaded the task");
        [self startLoadingFeatures];
    };
    
    NSLog(@"Monitored Regions: %@", self.locationManager.monitoredRegions);
}

- (CLLocationManager *)locationManager {
    if (!_locationManager) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _locationManager.desiredAccuracy = 100;
        _locationManager.distanceFilter = 10;
        _locationManager.allowsBackgroundLocationUpdates = YES;
        _locationManager.pausesLocationUpdatesAutomatically = YES;
        _locationManager.activityType = CLActivityTypeOther;
    }
    
    return _locationManager;
}



- (void)startLoadingFeatures {
    // For the simulator, use a fixed path on your computer. For a device, set to nil.
    // NSString *path = @"/Users/aaronpk/test";
    NSString *path = nil;
    [self.gdbTask generateGeodatabaseWithParameters:nil
                                 downloadFolderPath:path
                                        useExisting:YES
                                             status:^(AGSResumableTaskJobStatus status, NSDictionary *userInfo) {
        NSLog(@"Sync Status: %@", AGSResumableTaskJobStatusAsString(status));
    } completion:^(AGSGDBGeodatabase *geodatabase, NSError *error) {
        self.geodatabase = geodatabase;
        NSLog(@"Sync complete. Error: %@", error);
        [self findFeaturesInTable];
    }];
    
}

- (void)findFeaturesInTable {
    AGSQuery *query = [AGSQuery new];
    query.whereClause = @"1=1"; // Return all features. If you have more than 20, return the nearest 20 instead.
    for (AGSFeatureTable* featureTable in self.geodatabase.featureTables) {
        NSLog(@"Querying table for features");
        [featureTable queryResultsWithParameters:query completion:^(NSArray *results, NSError *error) {
            for (AGSGDBFeature* feature in results) {
                [self addGeofenceForFeature:feature];
            }
        }];
    }
}

- (void)findFeatureId:(NSString *)featureId completion:(void(^)(AGSGDBFeature *))completionBlock {
    AGSQuery *query = [AGSQuery new];
    query.objectIds = @[featureId];
    for (AGSFeatureTable* featureTable in self.geodatabase.featureTables) {
        [featureTable queryResultsWithParameters:query completion:^(NSArray *results, NSError *error) {
            for (AGSGDBFeature* feature in results) {
                completionBlock(feature);
            }
        }];
    }
}

- (void)addGeofenceForFeature:(AGSGDBFeature *)feature {
    NSLog(@"Processing feature: %lld %@", feature.objectID, [feature attributeAsStringForKey:@"Name"]);
    
    AGSGeometryEngine *geo = [AGSGeometryEngine defaultGeometryEngine];
    AGSSpatialReference *wgs84 = [AGSSpatialReference wgs84SpatialReference];

    // Find the center of the polygon
    AGSPoint *center = (AGSPoint *)[geo projectGeometry:feature.geometry.envelope.center
                                     toSpatialReference:wgs84];
    NSLog(@"Center: %@", [center encodeToJSON]);
    
    // Find a corner of the envelope of the polygon
    AGSEnvelope *envelope = feature.geometry.envelope;
    AGSPoint *corner = [AGSPoint pointWithX:envelope.xmax y:envelope.ymax spatialReference:envelope.spatialReference];
    corner = (AGSPoint *)[geo projectGeometry:corner toSpatialReference:wgs84];
    NSLog(@"Corner: %@", [corner encodeToJSON]);
    
    // Find the distance between the center and the corner of the envelope
    AGSGeodesicDistanceResult *distance = [geo geodesicDistanceBetweenPoint1:center
                                                                      point2:corner
                                                                      inUnit:AGSSRUnitMeter];
    NSLog(@"Distance: %f", distance.distance);
    
    // Create a CLRegion using the center point and distance
    NSString *objectID = [NSString stringWithFormat:@"%lld",feature.objectID];
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(center.y, center.x);
    CLCircularRegion *region = [[CLCircularRegion alloc] initWithCenter:coord
                                                                 radius:distance.distance
                                                             identifier:objectID];
    
    [self.locationManager startMonitoringForRegion:region];
    
}

-(void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    NSLog(@"Entered region: %@", region);
    [self findFeatureId:region.identifier completion:^(AGSGDBFeature *feature) {
        NSLog(@"Found Feature: %@", feature);

        UILocalNotification* localNotification = [[UILocalNotification alloc] init];
        localNotification.alertBody = [feature attributeAsStringForKey:@"Notification"];
        [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];

    }];
}

-(void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    NSLog(@"Exited region");
}

- (void)notify:(NSString *)message {
    UILocalNotification* localNotification = [[UILocalNotification alloc] init];
    localNotification.alertBody = message;
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
