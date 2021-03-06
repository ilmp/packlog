//
//  StatusManager.m
//  PackLog
//
//  Created by Jonathan George on 10/10/08.
//  Copyright 2008 JDG. All rights reserved.
//

#import "PackLogAppDelegate.h"
#import "StatusManager.h"
#import "TouchXML.h"
#import "Beacon.h"
#import "StatusEntryModel.h"

@implementation StatusManager

@synthesize statusEntries;

- (void) sendUpdateToJournal:(NSString *)entry {
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	PackLogAppDelegate *appDelegate = (PackLogAppDelegate *)[[UIApplication sharedApplication] delegate];
	NSHTTPURLResponse *resp = nil;
	NSError *error = nil;

	NSString *http = @"";
	if ([appDelegate.usesSSL isEqualToString:@"YES"]) {
		http = @"https";
	} else {
		http = @"http";
	}

	NSString *encodedUrl = [NSString stringWithFormat:@"%@://%@.backpackit.com/users/%@/status.xml", http, appDelegate.subdomain, appDelegate.userId];
	NSLog(@"Using URL: %@", encodedUrl);

	NSString *journalEntry = [NSString stringWithFormat:@"<request>\n<token>%@</token>\n<status>\n<message>%@</message>\n</status>\n</request>", appDelegate.apiKey, entry];

	NSLog(@"SENDING: %@", journalEntry);

	NSData *myRequestData = [ NSData dataWithBytes: [ journalEntry UTF8String ] length: [ journalEntry length ] ];

	NSMutableURLRequest *post = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:encodedUrl] cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10];
	[post setHTTPMethod:@"PUT"];
	[post setHTTPBody:myRequestData];
    [post setValue:@"application/xml" forHTTPHeaderField:@"Content-Type"];
	[post setValue:[NSString stringWithFormat: @"%d", [journalEntry length]] forHTTPHeaderField: @"Content-Length"];

	NSData *data = [NSURLConnection sendSynchronousRequest:post returningResponse:&resp error:&error];
	NSLog(@"Received response: %d bytes - response code: %d", [data length], [resp statusCode]);

	if ([resp statusCode] == 200) {
		// Nothing.  We can't determine (unlike w/ journal entries) whether or not we should have used SSL.
	} else if ([resp statusCode] == 403) {
		[appDelegate saveUserId:nil];
	}
	
	NSString *receivedString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	NSLog(@"Received data: %@", receivedString);
	[receivedString release];

	[[Beacon shared] startSubBeaconWithName:@"postStatus" timeSession:NO];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;	

	if (error) {
		NSLog(@"Error code is: %d", [error code]);
		return;
	}
}

- (void) fetch {
	PackLogAppDelegate *appDelegate = (PackLogAppDelegate *)[[UIApplication sharedApplication] delegate];

	if ([appDelegate isSetup] == NO) {
		NSLog(@"Not fetching journal entries - no user configured.");
		[[NSNotificationCenter defaultCenter] postNotificationName:@"StatusRefreshNotification" object:nil userInfo:nil];
		return;
	}	
	
	NSString *encodedUrl = [NSString stringWithFormat:@"http://%@.backpackit.com/statuses.xml?token=%@", appDelegate.subdomain, appDelegate.apiKey];
	NSURL *requestURL = [NSURL URLWithString:encodedUrl];
	NSLog(@"Using URL: %@", encodedUrl);
	
	[UIApplication sharedApplication].networkActivityIndicatorVisible = YES;

	NSMutableURLRequest *post = [NSMutableURLRequest requestWithURL:requestURL];
	[post setHTTPMethod: @"GET"];
	
	NSURLConnection *connection = [NSURLConnection connectionWithRequest:post delegate:self];
	
	if (connection) {
		NSLog(@"connected.");
		[connection retain];
		receivedData = [[NSMutableData data] retain];
	} else {
		NSLog(@"unable to connect.");
	}
}

int sortByTwoDates(id obj1, id obj2, void *context) {
	return [[NSDate dateWithNaturalLanguageString:[(NSDictionary *)obj2 objectForKey:(NSString *)context]]
			compare:[NSDate dateWithNaturalLanguageString:[(NSDictionary *)obj1 objectForKey:(NSString *)context]]];
}

- (void) convertXMLDocumentToEntries:(CXMLDocument *)xml
{
	if (statusEntries) {
		[statusEntries release];
	}
	
	statusEntries = [[NSMutableArray alloc] init];
    NSArray *resultNodes = [xml nodesForXPath:@"//status" error:nil];
	
	for (CXMLElement *resultElement in resultNodes) {
		
		NSMutableDictionary *blogItem = [[NSMutableDictionary alloc] init];
		
		int counter;
		int childCounter;
		NSString *parentName = @"";
		
		for(counter = 0; counter < [resultElement childCount]; counter++) {
			
			if ([[resultElement childAtIndex:counter] childCount] > 1) {
				parentName = [[resultElement childAtIndex:counter] name];
				
				for (childCounter = 0; childCounter < [[resultElement childAtIndex:counter] childCount]; childCounter++) {
					[blogItem setObject:[[[resultElement childAtIndex:counter] childAtIndex:childCounter] stringValue] forKey:[NSString stringWithFormat:@"%@_%@", parentName, [[[resultElement childAtIndex:counter] childAtIndex:childCounter] name]]];
				}
			} else {
				[blogItem setObject:[[resultElement childAtIndex:counter] stringValue] forKey:[[resultElement childAtIndex:counter] name]];
			}
		}
		
		// Add the blogItem to the global blogEntries Array so that the view can access it.
		[statusEntries addObject:[blogItem copy]];
	}

	[statusEntries sortUsingFunction:sortByTwoDates context:@"updated-at"];
	
	NSLog(@"statusEntries is: %@", statusEntries);
}

/*********** NSURLDelegate */
- (void)theConnection:(NSURLConnection *)theConnection
	 didFailWithError:(NSError *)error
{
    // release the connection, and the data object
    [theConnection release];
    // receivedData is declared as a method instance elsewhere
    [receivedData release];
	
    // inform the user
    NSLog(@"Connection failed! Error - %@ %@",
          [error localizedDescription],
          [[error userInfo] objectForKey:NSErrorFailingURLStringKey]);
	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    // append the new data to the receivedData
    // receivedData is declared as a method instance elsewhere
    [receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response
{
    // this method is called when the server has determined that it
    // has enough information to create the NSURLResponse
	
    // it can be called multiple times, for example in the case of a
    // redirect, so each time we reset the data.
    // receivedData is declared as a method instance elsewhere
    [receivedData setLength:0];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse
{
	if ([[[request URL] path] isEqualToString:@"/login"]) {
		NSLog(@"Login failed.  Need to display Settings screen.");
//		[[NSNotificationCenter defaultCenter] postNotificationName:@"SettingsNeedDisplayedNotification" object:nil userInfo:nil];
	}

	PackLogAppDelegate *appDelegate = (PackLogAppDelegate *)[[UIApplication sharedApplication] delegate];
	if ([[[request URL] scheme] isEqualToString:@"https"]) {
		NSLog(@"SCHEME: %@", [[request URL] scheme]);
		[appDelegate saveUsesSSL:@"YES"];
	} else {
		NSLog(@"SCHEME: %@", [[request URL] scheme]);
		[appDelegate saveUsesSSL:@"NO"];
	}

	NSLog(@"StatusManager: connection:willSendRequest:redirectResponse: request URL = %@, response URL = %@", [[request URL] path], [[redirectResponse URL] absoluteURL]);
	return request;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
	// do something with the data
    // receivedData is declared as a method instance elsewhere
    NSLog(@"Succeeded! Received %d bytes of data",[receivedData length]);
	
	CXMLDocument *xml = [[CXMLDocument alloc] initWithData:receivedData options:nil error:nil];
	[self convertXMLDocumentToEntries:xml];

	[UIApplication sharedApplication].networkActivityIndicatorVisible = NO;
	[[NSNotificationCenter defaultCenter] postNotificationName:@"StatusRefreshNotification" object:nil userInfo:nil];
	
	[connection release];
    [receivedData release];
}

@end
