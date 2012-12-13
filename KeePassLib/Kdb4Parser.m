/*
 * Copyright 2011 Jason Rush and John Flanagan. All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#import "Kdb4Parser.h"
#import "Kdb4Node.h"
#import "DDXML.h"
#import "DDXMLElementAdditions.h"
#import "DDXMLDocument+MKPAdditions.h"
#import "DDXMLElement+MKPAdditions.h"
#import "Base64.h"

#define FIELD_TITLE     @"Title"
#define FIELD_USER_NAME @"UserName"
#define FIELD_PASSWORD  @"Password"
#define FIELD_URL       @"URL"
#define FIELD_NOTES     @"Notes"

@interface Kdb4Parser (PrivateMethods)
- (void)decodeProtected:(DDXMLElement *)root;
- (void)parseMeta:(DDXMLElement *)root;
- (Kdb4Group *)parseGroup:(DDXMLElement *)root;
- (Kdb4Entry *)parseEntry:(DDXMLElement *)root;
@end

@implementation Kdb4Parser

- (id)initWithRandomStream:(RandomStream *)cryptoRandomStream {
    self = [super init];
    if (self) {
        randomStream = [cryptoRandomStream retain];
        
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.timeZone = [NSTimeZone timeZoneWithName:@"GMT"];
        dateFormatter.dateFormat = @"yyyy'-'MM'-'dd'T'HH':'mm':'ss'Z'";
    }
    return self;
}

- (void)dealloc {
    [randomStream release];
    [dateFormatter release];
    [super dealloc];
}

int	readCallback(void *context, char *buffer, int len) {
    InputStream *inputStream = (InputStream*)context;
    return [inputStream read:buffer length:len];
}

int closeCallback(void *context) {
    return 0;
}

- (Kdb4Tree *)parse:(InputStream *)inputStream {
    DDXMLDocument *document = [[DDXMLDocument alloc] initWithReadIO:readCallback closeIO:closeCallback context:inputStream options:0 error:nil];
    if (document == nil) {
        @throw [NSException exceptionWithName:@"ParseError" reason:@"Failed to parse database" userInfo:nil];
    }
    
    // Get the root document element
    DDXMLElement *rootElement = [document rootElement];
    
    // Decode all the protected entries
    [self decodeProtected:rootElement];

    DDXMLElement *meta = [rootElement elementForName:@"Meta"];
    if (meta != nil) {
        [self parseMeta:meta];
    }

    DDXMLElement *root = [rootElement elementForName:@"Root"];
    if (root == nil) {
        [document release];
        @throw [NSException exceptionWithName:@"ParseError" reason:@"Failed to parse database" userInfo:nil];
    }

    DDXMLElement *element = [root elementForName:@"Group"];
    if (element == nil) {
        [document release];
        @throw [NSException exceptionWithName:@"ParseError" reason:@"Failed to parse database" userInfo:nil];
    }
    
    Kdb4Tree *tree = [[Kdb4Tree alloc] init];
    tree.root = [self parseGroup:element];

    [document release];
    
    return [tree autorelease];
}

- (void)parseMeta:(DDXMLElement *)root {
    DDXMLElement *element = [root elementForName:@"HeaderHash"];
    if (element != nil) {
        [root removeChild:element];
    }
}

- (void)decodeProtected:(DDXMLElement *)root {
    DDXMLNode *protectedAttribute = [root attributeForName:@"Protected"];
    if ([[protectedAttribute stringValue] isEqual:@"True"]) {
        NSString *str = [root stringValue];
        
        // Base64 decode the string
        NSMutableData *data = [Base64 decode:[str dataUsingEncoding:NSASCIIStringEncoding]];
        
        // Unprotect the password
        [randomStream xor:data];
        
        NSString *unprotected = [[NSString alloc] initWithBytes:data.bytes length:data.length encoding:NSUTF8StringEncoding];
        [root setStringValue:unprotected];
        [unprotected release];
    }
    
    for (DDXMLNode *node in [root children]) {
        if ([node kind] == DDXMLElementKind) {
            [self decodeProtected:(DDXMLElement*)node];
        }
    }
}

- (Kdb4Group *)parseGroup:(DDXMLElement *)root {
    DDXMLElement *element;
    
    Kdb4Group *group = [[[Kdb4Group alloc] init] autorelease];

    element = [root elementForName:@"UUID"];
    [group.properties setValue:element.stringValue forKey:@"UUID"];

    element = [root elementForName:@"Name"];
    group.name =  element.stringValue;
    
    element = [root elementForName:@"Notes"];
    [group.properties setValue:element.stringValue forKey:@"Notes"];

    element = [root elementForName:@"IconID"];
    group.image = element.stringValue.integerValue;

    DDXMLElement *timesElement = [root elementForName:@"Times"];
    
    NSString *str = [[timesElement elementForName:@"LastModificationTime"] stringValue];
    group.lastModificationTime = [dateFormatter dateFromString:str];
    
    str = [[timesElement elementForName:@"CreationTime"] stringValue];
    group.creationTime = [dateFormatter dateFromString:str];

    str = [[timesElement elementForName:@"LastAccessTime"] stringValue];
    group.lastAccessTime = [dateFormatter dateFromString:str];
    
    str = [[timesElement elementForName:@"ExpiryTime"] stringValue];
    group.expiryTime = [dateFormatter dateFromString:str];

    str = [[timesElement elementForName:@"Expires"] stringValue];
    group.expires = [str isEqual:@"True"];

    str = [[timesElement elementForName:@"UsageCount"] stringValue];
    group.expires = [str integerValue];

    str = [[timesElement elementForName:@"LocationChanged"] stringValue];
    group.locationChanged = [dateFormatter dateFromString:str];

    element = [root elementForName:@"IsExpanded"];
    [group.properties setValue:element.stringValue forKey:@"IsExpanded"];

    element = [root elementForName:@"DefaultAutoTypeSequence"];
    [group.properties setValue:element.stringValue forKey:@"DefaultAutoTypeSequence"];

    element = [root elementForName:@"EnableAutoType"];
    [group.properties setValue:element.stringValue forKey:@"EnableAutoType"];

    element = [root elementForName:@"EnableSearching"];
    [group.properties setValue:element.stringValue forKey:@"EnableSearching"];

    element = [root elementForName:@"LastTopVisibleEntry"];
    [group.properties setValue:element.stringValue forKey:@"LastTopVisibleEntry"];

    for (DDXMLElement *element in [root elementsForName:@"Entry"]) {
        Kdb4Entry *entry = [self parseEntry:element];
        entry.parent = group;
        
        [group addEntry:entry];
    }
    
    for (DDXMLElement *element in [root elementsForName:@"Group"]) {
        Kdb4Group *subGroup = [self parseGroup:element];
        subGroup.parent = group;
        
        [group addGroup:subGroup];
    }
    
    return group;
}

- (Kdb4Entry *)parseEntry:(DDXMLElement *)root {
    DDXMLElement *element;
    
    Kdb4Entry *entry = [[[Kdb4Entry alloc] init] autorelease];

    element = [root elementForName:@"UUID"];
    [entry.properties setValue:element.stringValue forKey:@"UUID"];

    entry.image = [[[root elementForName:@"IconID"] stringValue] intValue];

    element = [root elementForName:@"ForegroundColor"];
    [entry.properties setValue:element.stringValue forKey:@"ForegroundColor"];

    element = [root elementForName:@"BackgroundColor"];
    [entry.properties setValue:element.stringValue forKey:@"BackgroundColor"];

    element = [root elementForName:@"OverrideURL"];
    [entry.properties setValue:element.stringValue forKey:@"OverrideURL"];

    element = [root elementForName:@"Tags"];
    [entry.properties setValue:element.stringValue forKey:@"Tags"];

    DDXMLElement *timesElement = [root elementForName:@"Times"];

    NSString *str = [[timesElement elementForName:@"LastModificationTime"] stringValue];
    entry.lastModificationTime = [dateFormatter dateFromString:str];

    str = [[timesElement elementForName:@"CreationTime"] stringValue];
    entry.creationTime = [dateFormatter dateFromString:str];

    str = [[timesElement elementForName:@"LastAccessTime"] stringValue];
    entry.lastAccessTime = [dateFormatter dateFromString:str];

    str = [[timesElement elementForName:@"ExpiryTime"] stringValue];
    entry.expiryTime = [dateFormatter dateFromString:str];

    str = [[timesElement elementForName:@"Expires"] stringValue];
    entry.expires = [str isEqual:@"True"];

    str = [[timesElement elementForName:@"UsageCount"] stringValue];
    entry.expires = [str integerValue];

    str = [[timesElement elementForName:@"LocationChanged"] stringValue];
    entry.locationChanged = [dateFormatter dateFromString:str];

    for (DDXMLElement *element in [root elementsForName:@"String"]) {
        NSString *key = [[element elementForName:@"Key"] stringValue];

        DDXMLElement *valueElement = [element elementForName:@"Value"];
        NSString *value = [valueElement stringValue];
        
        if ([key isEqualToString:FIELD_TITLE]) {
            entry.title = value;
        } else if ([key isEqualToString:FIELD_USER_NAME]) {
            entry.username = value;
        } else if ([key isEqualToString:FIELD_PASSWORD]) {
            entry.password = value;
        } else if ([key isEqualToString:FIELD_URL]) {
            entry.url = value;
        } else if ([key isEqualToString:FIELD_NOTES]) {
            entry.notes = value;
        } else {
            StringField *stringField = [[StringField alloc] init];
            stringField.key = key;
            stringField.value = value;
            stringField.protected = [[element attributeForName:@"Protected"] isEqual:@"True"];
            [entry.stringFields addObject:stringField];
        }
    }

    // FIXME Auto-type stuff goes here
    
    return entry;
}

@end
