//
//  FirstViewController.m
//  GeofencingDemo
//
//  Created by Aaron Parecki on 3/1/16.
//  Copyright © 2016 Aaron Parecki. All rights reserved.
//

#import "FirstViewController.h"
#import <ArcGIS/ArcGIS.h>

#define kFeatureServiceURL @"http://services.arcgis.com/rOo16HdIMeOBI4Mb/arcgis/rest/services/Sample_Triggers_for_Devsummit/FeatureServer"
//#define kFeatureServiceURL @"https://sampleserver6.arcgisonline.com/arcgis/rest/services/Sync/WildfireSync/FeatureServer"

@interface FirstViewController ()

@property (nonatomic, strong) AGSGDBGeodatabase *geodatabase;
@property (nonatomic, strong) AGSGDBSyncTask *gdbTask;
@property (nonatomic, strong) CLLocationManager *locationManager;

@end

@implementation FirstViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Need to run this to request authorization from the user.
    [self.locationManager requestAlwaysAuthorization];

    // Request permissions to send notifications
    UIUserNotificationSettings *mySettings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:mySettings];

    // Create the Geodatabase Task pointing to the feature service URL
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
    // Generate the sync task parameters
    AGSGDBGenerateParameters *params = [[AGSGDBGenerateParameters alloc] initWithFeatureServiceInfo:self.gdbTask.featureServiceInfo];
    
    // Palm Springs
    // NW 33.829191, -116.547623
    // SE 33.820457, -116.533533
    
    // params.extent = [AGSEnvelope envelopeWithXmin:-116.547623 ymin:33.820457 xmax:-116.533533 ymax:33.829191 spatialReference:[AGSSpatialReference wgs84SpatialReference]];
    
    // NSMutableArray* layers = [[NSMutableArray alloc] init];
    // for (AGSMapServiceLayerInfo* layerInfo in self.gdbTask.featureServiceInfo.layerInfos) {
    //    NSLog(@"Found layer ID: %lu", (unsigned long)layerInfo.layerId);
    //    [layers addObject:[NSNumber numberWithInt: (int)layerInfo.layerId]];
    // }
    // params.layerIDs = layers;
    
    // Generate a geodatabase on the device with the parameters above, which starts the sync
    // NSString *path = @"/Users/aaronpk/test";
    NSString *path = nil;
    [self.gdbTask generateGeodatabaseWithParameters:nil downloadFolderPath:path useExisting:YES status:^(AGSResumableTaskJobStatus status, NSDictionary *userInfo) {
        NSLog(@"Sync Status: %@", AGSResumableTaskJobStatusAsString(status));
    } completion:^(AGSGDBGeodatabase *geodatabase, NSError *error) {
        self.geodatabase = geodatabase;
        NSLog(@"Sync complete. Error: %@", error);
        //NSLog(@"Found table: %@", self.geodatabase);
        [self.locationManager startUpdatingLocation];
        [self findFeaturesInTable];
    }];
}

- (void)findFeaturesInTable {
    AGSQuery *query = [AGSQuery new];
    query.whereClause = @"1=1"; // Return all features
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
    //NSLog(@"%@", feature);
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
    AGSGeodesicDistanceResult *distance = [geo geodesicDistanceBetweenPoint1:center point2:corner inUnit:AGSSRUnitMeter];
    NSLog(@"Distance: %f", distance.distance);
    
    // Create a CLRegion
    CLLocationCoordinate2D coord = CLLocationCoordinate2DMake(center.y, center.x);
    CLCircularRegion *region = [[CLCircularRegion alloc] initWithCenter:coord radius:distance.distance identifier:[NSString stringWithFormat:@"%lld",feature.objectID]];
    
    [self.locationManager startMonitoringForRegion:region];
    
}

-(void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    NSLog(@"Entered region: %@", region);
    [self findFeatureId:region.identifier completion:^(AGSGDBFeature *feature) {
        NSLog(@"Found Feature: %@", feature);
        [self notify:[feature attributeAsStringForKey:@"Notification"]];
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
