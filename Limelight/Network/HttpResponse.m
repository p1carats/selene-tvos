//
//  HttpResponse.m
//  Moonlight
//
//  Created by Diego Waxemberg on 1/30/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

#import "HttpResponse.h"
#import "Logger.h"

@interface HttpResponse () <NSXMLParserDelegate>

@property (nonatomic, strong) NSMutableDictionary* elements;
@property (nonatomic, strong) NSMutableString* currentElementValue;
@property (nonatomic, strong) NSString* currentElementName;

@end

@implementation HttpResponse

@synthesize data, statusCode, statusMessage;

- (void) populateWithData:(NSData*)xml {
    self.data = xml;
    [self parseData];
}

- (NSString*) getStringTag:(NSString*)tag {
    return [self.elements objectForKey:tag];
}

- (BOOL) getIntTag:(NSString *)tag value:(NSInteger*)value {
    NSString* stringVal = [self getStringTag:tag];
    if (stringVal != nil) {
        *value = [stringVal integerValue];
        return true;
    } else {
        return false;
    }
}

- (BOOL) isStatusOk {
    return self.statusCode == 200;
}

- (void) parseData {
    self.elements = [[NSMutableDictionary alloc] init];
    self.currentElementValue = [[NSMutableString alloc] init];
    
    NSXMLParser* parser = [[NSXMLParser alloc] initWithData:self.data];
    parser.delegate = self;
    
    if (![parser parse]) {
        Log(LOG_W, @"An error occurred trying to parse xml: %@", parser.parserError);
        return;
    }
    
    Log(LOG_D, @"Parsed XML data: %@", self.elements);
}

#pragma mark - NSXMLParserDelegate

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary<NSString *,NSString *> *)attributeDict {
    // Handle root element attributes (status code and message)
    if ([elementName isEqualToString:@"root"] || self.statusCode == 0) {
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
        
        // Special case handling for audio capture error
        if (self.statusCode == -1 && [self.statusMessage isEqualToString:@"Invalid"]) {
            self.statusCode = 418;
            self.statusMessage = @"Missing audio capture device. Reinstalling GeForce Experience should resolve this error.";
        }
    }
    
    // Reset current element tracking
    self.currentElementName = elementName;
    [self.currentElementValue setString:@""];
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
    [self.currentElementValue appendString:string];
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName {
    if (self.currentElementName && ![elementName isEqualToString:@"root"]) {
        // Store the element value in our dictionary
        NSString* value = [self.currentElementValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (value == nil) {
            value = @"";
        }
        [self.elements setObject:value forKey:elementName];
    }
    
    // Clear current element tracking
    self.currentElementName = nil;
    [self.currentElementValue setString:@""];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
    Log(LOG_W, @"XML Parse error: %@", parseError);
}

@end
