//
//  AppListResponse.m
//  Moonlight
//
//  Created by Diego Waxemberg on 2/1/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "AppListResponse.h"
#import "TemporaryApp.h"
#import "Logger.h"

@interface AppListResponse () <NSXMLParserDelegate>

@property (nonatomic, strong) NSMutableSet* appList;
@property (nonatomic, strong) NSMutableString* currentElementValue;
@property (nonatomic, strong) NSString* currentElementName;
@property (nonatomic, strong) TemporaryApp* currentApp;
@property (nonatomic, assign) BOOL inAppElement;

@end

@implementation AppListResponse

@synthesize data, statusCode, statusMessage;

static NSString* const TAG_APP = @"App";
static NSString* const TAG_APP_TITLE = @"AppTitle";
static NSString* const TAG_APP_ID = @"ID";
static NSString* const TAG_HDR_SUPPORTED = @"IsHdrSupported";
static NSString* const TAG_APP_INSTALL_PATH = @"AppInstallPath";

- (void)populateWithData:(NSData *)xml {
    self.data = xml;
    self.appList = [[NSMutableSet alloc] init];
    [self parseData];
}

- (void) parseData {
    self.currentElementValue = [[NSMutableString alloc] init];
    self.inAppElement = NO;
    
    NSXMLParser* parser = [[NSXMLParser alloc] initWithData:self.data];
    parser.delegate = self;
    
    if (![parser parse]) {
        Log(LOG_W, @"An error occurred trying to parse xml: %@", parser.parserError);
        return;
    }
}

- (NSSet*) getAppList {
    return self.appList;
}

- (BOOL) isStatusOk {
    return self.statusCode == 200;
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    
    // Handle root element attributes (status code and message)
    if (self.statusCode == 0) {
        NSString* statusCodeStr = attributeDict[TAG_STATUS_CODE];
        if (statusCodeStr) {
            self.statusCode = [statusCodeStr integerValue];
        }
        
        NSString* statusMsg = attributeDict[TAG_STATUS_MESSAGE];
        if (statusMsg) {
            self.statusMessage = statusMsg;
        } else {
            self.statusMessage = @"Server Error";
        }
    }
    
    // Check if we're starting an App element
    if ([elementName isEqualToString:TAG_APP]) {
        self.inAppElement = YES;
        self.currentApp = [[TemporaryApp alloc] init];
        // Initialize defaults
        self.currentApp.name = @"";
        self.currentApp.hdrSupported = NO;
    }
    
    // Reset current element tracking
    self.currentElementName = elementName;
    [self.currentElementValue setString:@""];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentElementValue appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    
    if (self.inAppElement && self.currentApp) {
        NSString* value = [self.currentElementValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value == nil) {
            value = @"";
        }
        
        if ([elementName isEqualToString:TAG_APP_TITLE]) {
            self.currentApp.name = value;
        } else if ([elementName isEqualToString:TAG_APP_ID]) {
            self.currentApp.id = value;
        } else if ([elementName isEqualToString:TAG_HDR_SUPPORTED]) {
            self.currentApp.hdrSupported = [value intValue] != 0;
        } else if ([elementName isEqualToString:TAG_APP_INSTALL_PATH]) {
            self.currentApp.installPath = value;
        }
    }
    
    // Check if we're ending an App element
    if ([elementName isEqualToString:TAG_APP]) {
        self.inAppElement = NO;
        if (self.currentApp && self.currentApp.id != nil) {
            [self.appList addObject:self.currentApp];
        }
        self.currentApp = nil;
    }
    
    // Clear current element tracking
    self.currentElementName = nil;
    [self.currentElementValue setString:@""];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    Log(LOG_W, @"XML Parse error: %@", parseError);
}

@end
