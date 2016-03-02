//
//  FirstViewController.m
//  GeofencingDemo
//
//  Created by Aaron Parecki on 3/1/16.
//  Copyright © 2016 Aaron Parecki. All rights reserved.
//

#import "FirstViewController.h"
#import <ArcGIS/ArcGIS.h>

#define kFeatureServiceURL @"https://services.arcgis.com/rOo16HdIMeOBI4Mb/ArcGIS/rest/services/SampleTriggersPalmSprings/FeatureServer"
//#define kFeatureServiceURL @"https://sampleserver6.arcgisonline.com/arcgis/rest/services/Sync/WildfireSync/FeatureServer"

@interface FirstViewController ()

@property (nonatomic, strong) AGSGDBGeodatabase *geodatabase;
@property (nonatomic, strong) AGSGDBSyncTask *gdbTask;

@end

@implementation FirstViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Create the Geodatabase Task pointing to the feature service URL
    self.gdbTask = [[AGSGDBSyncTask alloc] initWithURL:[NSURL URLWithString:kFeatureServiceURL]];

    self.gdbTask.loadCompletion = ^(NSError* error){
        NSLog(@"Loaded the task");
        [self findFeaturesInTable];
        // [self startLoadingFeatures];
    };
}

- (void)startLoadingFeatures {
    // Generate the sync task parameters
    AGSGDBGenerateParameters *params = [[AGSGDBGenerateParameters alloc] initWithFeatureServiceInfo:self.gdbTask.featureServiceInfo];
    
    // Palm Springs
    // NW 33.829191, -116.547623
    // SE 33.820457, -116.533533
    
    params.extent = [AGSEnvelope envelopeWithXmin:-116.547623 ymin:33.820457 xmax:-116.533533 ymax:33.829191 spatialReference:[AGSSpatialReference wgs84SpatialReference]];
    
    NSMutableArray* layers = [[NSMutableArray alloc] init];
    for (AGSMapServiceLayerInfo* layerInfo in self.gdbTask.featureServiceInfo.layerInfos) {
        NSLog(@"Found layer ID: %lu", (unsigned long)layerInfo.layerId);
        [layers addObject:[NSNumber numberWithInt: (int)layerInfo.layerId]];
    }
    params.layerIDs = layers;
    
    // Generate a geodatabase on the device with the parameters above, which starts the sync
    [self.gdbTask generateGeodatabaseWithParameters:params downloadFolderPath:nil useExisting:YES status:^(AGSResumableTaskJobStatus status, NSDictionary *userInfo) {
        NSLog(@"Sync Status: %@", AGSResumableTaskJobStatusAsString(status));
    } completion:^(AGSGDBGeodatabase *geodatabase, NSError *error) {
        self.geodatabase = geodatabase;
        NSLog(@"Sync complete. Error: %@", error);
        NSLog(@"Found table: %@", self.geodatabase);
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

- (void)addGeofenceForFeature:(AGSGDBFeature *)feature {
    NSLog(@"Processing feature: %@", [feature attributeAsStringForKey:@"title"]);
    NSLog(@"Center: %@", feature.geometry.envelope.center);
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
