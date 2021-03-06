/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 * 
 * Copyright (c) 2005-2010, Nitobi Software Inc.
 * Copyright (c) 2011, IBM Corporation
 */


#import "File.h"
#import <Categories.h>
#import <JSON.h>
#import <NSData+Base64.h>
#import <MobileCoreServices/MobileCoreServices.h>


@implementation File

@synthesize appDocsPath, appLibraryPath, appTempPath, persistentPath, temporaryPath, userHasAllowed;



-(id)initWithWebView:(UIWebView *)theWebView
{
	self = (File*)[super initWithWebView:theWebView];
	if(self)
	{
		// get the documents directory path
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		self.appDocsPath = [paths objectAtIndex:0];
		
		paths = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
		self.appLibraryPath = [paths objectAtIndex:0];
		
		self.appTempPath =  [NSTemporaryDirectory() stringByStandardizingPath]; // remove trailing slash from NSTemporaryDirectory()
		
		self.persistentPath = [NSString stringWithFormat: @"/%@",[self.appDocsPath lastPathComponent]];
		self.temporaryPath = [NSString stringWithFormat: @"/%@",[self.appTempPath lastPathComponent]];
		//NSLog(@"docs: %@ - temp: %@", self.appDocsPath, self.appTempPath);
	}
	
	return self;
}
- (NSNumber*) checkFreeDiskSpace: (NSString*) appPath
{
	NSFileManager* fMgr = [[NSFileManager alloc] init];
	
	NSError* pError = nil;
	
	NSDictionary* pDict = [ fMgr attributesOfFileSystemForPath:appPath error:&pError ];
	NSNumber* pNumAvail = (NSNumber*)[ pDict objectForKey:NSFileSystemFreeSize ];
	[fMgr release];
	return pNumAvail;
	
}
// figure out if the pathFragment represents a persistent of temporary directory and return the full application path.
// returns nil if path is not persistent or temporary
-(NSString*) getAppPath: (NSString*)pathFragment
{
	NSString* appPath = nil;
	NSRange rangeP = [pathFragment rangeOfString:self.persistentPath];
	NSRange rangeT = [pathFragment rangeOfString:self.temporaryPath];
	
	if (rangeP.location != NSNotFound && rangeT.location != NSNotFound){
		// we found both in the path, return whichever one is first
		if (rangeP.length < rangeT.length) {
			appPath = self.appDocsPath;
		}else {
			appPath = self.appTempPath;
		}
	} else if (rangeP.location != NSNotFound) {
		appPath = self.appDocsPath;
	} else if (rangeT.location != NSNotFound){
		appPath = self.appTempPath;
	}
	return appPath;
}
/* get the full path to this resource
 * IN
 *	NSString* pathFragment - full Path from File or Entry object (includes system path info)
 * OUT
 *	NSString* fullPath - full iOS path to this resource,  nil if not found
 */
/*  Was here in order to NOT have to return full path, but W3C synchronous DirectoryEntry.toURI() killed that idea since I can't call into iOS to 
 * resolve full URI.  Leaving this code here in case W3C spec changes. 
-(NSString*) getFullPath: (NSString*)pathFragment
{
	return pathFragment;
	NSString* fullPath = nil;
	NSString *appPath = [ self getAppPath: pathFragment];
	if (appPath){

		// remove last component from appPath
		NSRange range = [appPath rangeOfString:@"/" options: NSBackwardsSearch];
		NSString* newPath = [appPath substringToIndex:range.location];
		// add pathFragment to get test Path
		fullPath = [newPath stringByAppendingPathComponent:pathFragment];
	}
	return fullPath;
} */
/* Request the File System info
 *
 * IN:
 * arguments[0] - type (number as string)
 *	TEMPORARY = 0, PERSISTENT = 1;
 *
 * OUT:
 *	Dictionary representing FileSystem object
 *		name - the human readable directory name
 *		root = DirectoryEntry object
 *			bool isDirectory
 *			bool isFile
 *			string name
 *			string fullPath
 *			fileSystem = FileSystem object - !! ignored because creates circular reference !!
 */

- (void) requestFileSystem:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* strType = [arguments objectAtIndex: 1];
	int type = [strType intValue];
	unsigned long long size = [[arguments objectAtIndex:2] longLongValue];
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	if (type > 1){
		result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: NOT_FOUND_ERR cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
		NSLog(@"iOS only supports TEMPORARY and PERSISTENT file systems");
	} else {
		
		//NSString* fullPath = [NSString stringWithFormat:@"/%@", (type == 0 ? [self.appTempPath lastPathComponent] : [self.appDocsPath lastPathComponent])];
		NSString* fullPath = (type == 0 ? self.appTempPath  : self.appDocsPath);
		// check for avail space for size request
		NSNumber* pNumAvail = [self checkFreeDiskSpace: fullPath];
		//NSLog(@"Free space: %@", [NSString stringWithFormat:@"%qu", [ pNumAvail unsignedLongLongValue ]]);
		if (pNumAvail && [pNumAvail unsignedLongLongValue] < size) {
			result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: QUOTA_EXCEEDED_ERR cast: @"window.localFileSystem._castError"];
			jsString = [result toErrorCallbackString:callbackId];
		} 
		else {
			NSMutableDictionary* fileSystem = [NSMutableDictionary dictionaryWithCapacity:2];
			[fileSystem setObject: (type == TEMPORARY ? kW3FileTemporary : kW3FilePersistent)forKey:@"name"];
			NSDictionary* dirEntry = [self getDirectoryEntry: fullPath isDirectory: YES];
			[fileSystem setObject:dirEntry forKey:@"root"];
			result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsDictionary: fileSystem cast: @"window.localFileSystem._castFS"];
			jsString = [result toSuccessCallbackString:callbackId];
			//jsCallback = [NSString stringWithFormat:@"window.fileSystem.localFileSystem._requestFileSystemCB(%@);",[fileSystem JSONRepresentation]];
		}
	}
	[self writeJavascript: jsString];
	
}
/* Creates a dictionary representing an Entry Object
 *
 * IN:
 * NSString* fullPath of the entry 
 * FileSystem type 
 * BOOL isDirectory - YES if this is a directory, NO if is a file
 * OUT:
 * NSDictionary*
 Entry object
 *		bool as NSNumber isDirectory
 *		bool as NSNumber isFile
 *		NSString*  name - last part of path
 *		NSString* fullPath
 *		fileSystem = FileSystem object - !! ignored because creates circular reference FileSystem contains DirectoryEntry which contains FileSystem.....!!
 */
-(NSDictionary*) getDirectoryEntry: (NSString*) fullPath  isDirectory: (BOOL) isDir
{
	
	NSMutableDictionary* dirEntry = [NSMutableDictionary dictionaryWithCapacity:4];
	NSString* lastPart = [fullPath lastPathComponent];
	
	
	
	[dirEntry setObject:[NSNumber numberWithBool: !isDir]  forKey:@"isFile"];
	[dirEntry setObject:[NSNumber numberWithBool: isDir]  forKey:@"isDirectory"];
	//NSURL* fileUrl = [NSURL fileURLWithPath:fullPath];
	//[dirEntry setObject: [fileUrl absoluteString] forKey: @"fullPath"];
	[dirEntry setObject: fullPath forKey: @"fullPath"];
	[dirEntry setObject: lastPart forKey:@"name"];
	
	
	return dirEntry;
	
}
/*
 * Given a URI determine the File System information associated with it and return an appropriate W3C entry object
 * IN
 *	NSString* fileURI  - currently requires full file URI 
 * OUT
 *	Entry object
 *		bool isDirectory
 *		bool isFile
 *		string name
 *		string fullPath
 *		fileSystem = FileSystem object - !! ignored because creates circular reference FileSystem contains DirectoryEntry which contains FileSystem.....!!
 */
- (void) resolveLocalFileSystemURI:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* jsString = nil;
	NSString* inputUri = [arguments objectAtIndex:1];
	NSString* strUri = [inputUri stringByAddingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
	NSURL* testUri = [NSURL URLWithString:strUri];  //needs to be encoded when creating NSURL
	PluginResult* result = nil;
	
	if (!testUri || ![testUri isFileURL]) {
		// issue ENCODING_ERR
		result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: ENCODING_ERR cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
		//jsString = [NSString stringWithFormat:@"window.fileSystem.localFileSystem._errorCB(%d)", ENCODING_ERR];
	} else {
		NSFileManager* fileMgr = [[NSFileManager alloc] init];
		NSString* path = [testUri path];
		//NSLog(@"url path: %@", path);
		BOOL	isDir;
		// see if exists and is file or dir
		BOOL bExists = [fileMgr fileExistsAtPath:path isDirectory: &isDir];
		if (bExists) {
			// see if it contains docs path
			NSRange range = [path rangeOfString:self.appDocsPath];
			NSString* foundFullPath = nil;
			// there's probably an api or easier way to figure out the path type but I can't find it!
			if (range.location != NSNotFound &&  range.length == [self.appDocsPath length]){
				foundFullPath = self.appDocsPath;
			}else {
				// see if it contains the temp path
				range = [path rangeOfString:self.appTempPath];
				if (range.location != NSNotFound && range.length == [self.appTempPath length]){
					foundFullPath = self.appTempPath;
				}
			}
			if (foundFullPath == nil) {
				// error SECURITY_ERR - not one of the two paths types supported
				result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: SECURITY_ERR cast: @"window.localFileSystem._castError"];
				jsString = [result toErrorCallbackString:callbackId];
			} else {
				NSDictionary* fileSystem = [self getDirectoryEntry: path isDirectory: isDir];
				result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsDictionary: fileSystem cast: @"window.localFileSystem._castEntry"];
				jsString = [result toSuccessCallbackString:callbackId];
								
			}
		
		} else {
			// return NOT_FOUND_ERR
			result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: NOT_FOUND_ERR cast: @"window.localFileSystem._castError"];
			jsString = [result toErrorCallbackString:callbackId];
			
		}

		// use NSString URL access methods - NSURL methods are more efficient but only avail as of iOS 4.0 
		//NSArray* parts = [strUri pathComponents];
		//NSLog(@"file uri parts %@", [parts componentsJoinedByString:@" : "]);
		[fileMgr release];
	}
	if (jsString != nil){
		[self writeJavascript:jsString];
	}

}
/* Part of DirectoryEntry interface,  creates or returns the specified directory
 * IN:
 *	NSString* fullPath - full path for this directory 
 *	NSString* path - directory to be created/returned; may be full path or relative path
 *	NSDictionary* - Flags object
 *		boolean as NSNumber create - 
 *			if create is true and directory does not exist, create dir and return directory entry
 *			if create is true and exclusive is true and directory does exist, return error
 *			if create is false and directory does not exist, return error
 *			if create is false and the path represents a file, return error
 *		boolean as NSNumber exclusive - used in conjunction with create
 *			if exclusive is true and create is true - specifies failure if directory already exists
 *			
 *			
 */
- (void) getDirectory:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	// add getDir to options and call getFile()
	if (!options){
		options = [NSMutableDictionary dictionaryWithCapacity:1];
	}
	[options setObject:[NSNumber numberWithInt:1] forKey:@"getDir"];
	
	[self getFile: arguments withDict: options];


}
/* Part of DirectoryEntry interface,  creates or returns the specified file
 * IN:
 *	NSString* fullPath - full path for this file 
 *	NSString* path - file to be created/returned; may be full path or relative path
 *	NSDictionary* - Flags object
 *		boolean as NSNumber create - 
 *			if create is true and file does not exist, create file and return File entry
 *			if create is true and exclusive is true and file does exist, return error
 *			if create is false and file does not exist, return error
 *			if create is false and the path represents a directory, return error
 *		boolean as NSNumber exclusive - used in conjunction with create
 *			if exclusive is true and create is true - specifies failure if file already exists
 *			
 *			
 */
- (void) getFile: (NSMutableArray*) arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	// arguments are URL encoded
	NSString* fullPath = [arguments objectAtIndex:1];
	NSString* requestedPath = [arguments objectAtIndex:2];
	NSString* jsString = nil;
	PluginResult* result = nil;
	BOOL bDirRequest = NO;
	BOOL create = NO;
	BOOL exclusive = NO;
	int errorCode = 0;  // !!! risky - no error code currently defined for 0
	
	if ([options valueForKeyIsNumber:@"create"]) {
		create = [(NSNumber*)[options valueForKey: @"create"] boolValue];
	}
	if ([options valueForKeyIsNumber:@"exclusive"]) {
		exclusive = [(NSNumber*)[options valueForKey: @"exclusive"] boolValue];
	}
	
	if ([options valueForKeyIsNumber:@"getDir"]) {
		// this will not exist for calls directly to getFile but will have been set by getDirectory before calling this method
		bDirRequest = [(NSNumber*)[options valueForKey: @"getDir"] boolValue];
	}
	// see if the requested path has invalid characters - should we be checking for  more than just ":"?
	if ([requestedPath rangeOfString: @":"].location != NSNotFound) {
		errorCode = ENCODING_ERR;
	}	else {
			
		// was full or relative path provided?
		NSRange range = [requestedPath rangeOfString:fullPath];
		BOOL bIsFullPath = range.location != NSNotFound;
		
		NSString* reqFullPath = nil;
		
		if (!bIsFullPath) {
			reqFullPath = [fullPath stringByAppendingPathComponent:requestedPath];
		} else {
			reqFullPath = requestedPath;
		}
		
		//NSLog(@"reqFullPath = %@", reqFullPath);
		NSFileManager* fileMgr = [[NSFileManager alloc] init];
		BOOL bIsDir;
		BOOL bExists = [fileMgr fileExistsAtPath: reqFullPath isDirectory: &bIsDir];
		if (bExists && create == NO && bIsDir == !bDirRequest) {
			// path exists and is of requested type  - return TYPE_MISMATCH_ERR
			errorCode = TYPE_MISMATCH_ERR;
		} else if (!bExists && create == NO) {
			// path does not exist and create is false - return NOT_FOUND_ERR
			errorCode = NOT_FOUND_ERR;
		} else if (bExists && create == YES && exclusive == YES) {
			// file/dir already exists and exclusive and create are both true - return PATH_EXISTS_ERR
			errorCode = PATH_EXISTS_ERR;
		} else { 
			// if bExists and create == YES - just return data
			// if bExists and create == NO  - just return data
			// if !bExists and create == YES - create and return data
			BOOL bSuccess = YES;
			NSError* pError = nil;
			if(!bExists && create == YES){
				if(bDirRequest) {
					// create the dir
					bSuccess = [ fileMgr createDirectoryAtPath:reqFullPath withIntermediateDirectories:NO attributes:nil error:&pError];
				} else {
					// create the empty file
					bSuccess = [ fileMgr createFileAtPath:reqFullPath contents: nil attributes:nil];
				}
			}
			if(!bSuccess){
				errorCode = ABORT_ERR;
				if (pError) {
					NSLog(@"error creating directory: %@", [pError localizedDescription]);
				}
			} else {
				//NSLog(@"newly created file/dir (%@) exists: %d", reqFullPath, [fileMgr fileExistsAtPath:reqFullPath]);
				// file existed or was created
				result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsDictionary: [self getDirectoryEntry: reqFullPath isDirectory: bDirRequest] cast: @"window.localFileSystem._castEntry"];
				jsString = [result toSuccessCallbackString: callbackId];
			}
		} // are all possible conditions met?
		[fileMgr release];
	} 

	
	if (errorCode > 0) {
		// create error callback
		result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: errorCode cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
		//jsCallback = [NSString stringWithFormat:@"navigator.fileMgr._entryErrorCB(%d)", errorCode];
	}
	
	
	
	[self writeJavascript:jsString];
}
/* 
 * Look up the parent Entry containing this Entry. 
 * If this Entry is the root of its filesystem, its parent is itself.
 * IN: 
 * NSArray* arguments
 *	0 - NSString* callbackId
 *	1 - NSString* fullPath
 * NSMutableDictionary* options
 *	empty
 */
- (void) getParent:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	// arguments are URL encoded
	NSString* fullPath = [arguments objectAtIndex:1];
	PluginResult* result = nil;
	NSString* jsString = nil;
	NSString* newPath = nil;
	
	
	if ([fullPath isEqualToString:self.appDocsPath] || [fullPath isEqualToString: self.appTempPath]){
		// return self
		newPath = fullPath;
		
	} else {
		// since this call is made from an existing Entry object - the parent should already exist so no additional error checking
		// remove last component and return Entry
		NSRange range = [fullPath rangeOfString:@"/" options: NSBackwardsSearch];
		newPath = [fullPath substringToIndex:range.location];
	}

	if(newPath){
		NSFileManager* fileMgr = [[NSFileManager alloc] init];
		BOOL bIsDir;
		BOOL bExists = [fileMgr fileExistsAtPath: newPath isDirectory: &bIsDir];
		if (bExists) {
			result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsDictionary: [self getDirectoryEntry:newPath isDirectory:bIsDir] cast: @"window.localFileSystem._castEntry"];
			jsString = [result toSuccessCallbackString:callbackId];
		}
		[fileMgr release];
	}
	if (!jsString) {
		// invalid path or file does not exist
		result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: NOT_FOUND_ERR cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString: callbackId];
	}
	[self writeJavascript:jsString];

}
/*
 * get MetaData of entry
 * Currently MetaData only includes modificationTime.
 */
- (void) getMetadata:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	NSString* testPath = argPath; //[self getFullPath: argPath];
	
	NSFileManager* fileMgr = [[NSFileManager alloc] init];
	NSError* error = nil;
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	NSDictionary* fileAttribs = [fileMgr attributesOfItemAtPath:testPath error:&error];
	
	if (fileAttribs){
		NSDate* modDate = [fileAttribs fileModificationDate];
		if (modDate){
			NSNumber* msDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970]*1000];
			NSMutableDictionary* metadataDict = [NSMutableDictionary dictionaryWithCapacity:1];
			[metadataDict setObject:msDate forKey:@"modificationTime"];
			result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsDictionary: metadataDict cast: @"window.localFileSystem._castDate"];
			jsString = [result toSuccessCallbackString:callbackId];
		}
	} else {
		// didn't get fileAttribs
		FileError errorCode = ABORT_ERR;
		NSLog(@"error getting metadata: %@", [error localizedDescription]);
		if ([error code] == NSFileNoSuchFileError) {
			errorCode = NOT_FOUND_ERR;
		}
		// log [NSNumber numberWithDouble: theMessage] objCtype to see what it returns
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: errorCode cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	}
	if (jsString){
		[self writeJavascript:jsString];
	}
	[fileMgr release];
}

/* removes the directory or file entry
 * IN: 
 * NSArray* arguments
 *	0 - NSString* callbackId
 *	1 - NSString* fullPath
 * NSMutableDictionary* options
 *	empty
 *
 * returns NO_MODIFICATION_ALLOWED_ERR  if is top level directory or no permission to delete dir
 * returns INVALID_MODIFICATION_ERR if is dir and is not empty
 * returns NOT_FOUND_ERR if file or dir is not found
*/
- (void) remove:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* fullPath = [arguments objectAtIndex:1];
	
	PluginResult* result = nil;
	NSString* jsString = nil;
	FileError errorCode = 0;  // !! 0 not currently defined 
	
	
	// error if try to remove top level (documents or tmp) dir
	if ([fullPath isEqualToString:self.appDocsPath] || [fullPath isEqualToString:self.appTempPath]){
		errorCode = NO_MODIFICATION_ALLOWED_ERR;
	} else {
		NSFileManager* fileMgr = [[ NSFileManager alloc] init];
		BOOL bIsDir = NO;
		BOOL bExists = [fileMgr fileExistsAtPath:fullPath isDirectory: &bIsDir];
		if (!bExists){
			errorCode = NOT_FOUND_ERR;
		}
		if (bIsDir &&  [[fileMgr contentsOfDirectoryAtPath:fullPath error: nil] count] != 0) {
			// dir is not empty
			errorCode = INVALID_MODIFICATION_ERR;
		}
		[fileMgr release];
	}
	if (errorCode > 0) {
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: errorCode cast:@"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	} else {
		// perform actual remove
		jsString = [self doRemove: fullPath callback: callbackId];
	}
	[self writeJavascript:jsString];

}
/* recurvsively removes the directory 
 * IN: 
 * NSArray* arguments
 *	0 - NSString* callbackId
 *	1 - NSString* fullPath
 * NSMutableDictionary* options
 *	empty
 *
 * returns NO_MODIFICATION_ALLOWED_ERR  if is top level directory or no permission to delete dir
 * returns NOT_FOUND_ERR if file or dir is not found
 */
- (void) removeRecursively:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* fullPath = [arguments objectAtIndex:1];
	
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	// error if try to remove top level (documents or tmp) dir
	if ([fullPath isEqualToString:self.appDocsPath] || [fullPath isEqualToString:self.appTempPath]){
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: NO_MODIFICATION_ALLOWED_ERR cast:@"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	} else {
		jsString = [self doRemove: fullPath callback: callbackId];
	}
	
	[self writeJavascript:jsString];

}
/* remove the file or directory (recursively)
 * IN:
 * NSString* fullPath - the full path to the file or directory to be removed
 * NSString* callbackId
 * called from remove and removeRecursively - check all pubic api specific error conditions (dir not empty, etc) before calling
 */

- (NSString*) doRemove:(NSString*)fullPath callback: (NSString*)callbackId
{
	PluginResult* result = nil;
	NSString* jsString = nil;
	BOOL bSuccess = NO;
	NSError* pError = nil;
	NSFileManager* fileMgr = [[ NSFileManager alloc] init];

	@try {
		bSuccess = [ fileMgr removeItemAtPath:fullPath error:&pError];
		if (bSuccess) {
			PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK ];
			jsString = [result toSuccessCallbackString:callbackId];
		} else {
			// see if we can give a useful error
			FileError errorCode = ABORT_ERR;
			NSLog(@"error getting metadata: %@", [pError localizedDescription]);
			if ([pError code] == NSFileNoSuchFileError) {
				errorCode = NOT_FOUND_ERR;
			} else if ([pError code] == NSFileWriteNoPermissionError) {
				errorCode = NO_MODIFICATION_ALLOWED_ERR;
			}
			
			result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: errorCode cast: @"window.localFileSystem._castError"];
			jsString = [result toErrorCallbackString:callbackId];
		}
	} @catch (NSException* e) { // NSInvalidArgumentException if path is . or ..
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: SYNTAX_ERR cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];	
	}
	@finally {
		[fileMgr release];
		return jsString;
	}
}
- (void) copyTo:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	[self doCopyMove:arguments withDict:options isCopy:YES];
}
- (void) moveTo:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	[self doCopyMove:arguments withDict:options isCopy:NO];
}
/* Copy/move a file or directory to a new location
 * IN: 
 * NSArray* arguments
 *	0 - NSString* callbackId
 *	1 - NSString* fullPath of entry
 *  2 - NSString* newName the new name of the entry, defaults to the current name
 *	NSMutableDictionary* options - DirectoryEntry to which to copy the entry
 *	BOOL - bCopy YES if copy, NO if move
 * 
 */
- (void) doCopyMove:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options  isCopy:(BOOL)bCopy
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* srcFullPath = [arguments objectAtIndex:1];
	NSString* newName = nil;
	PluginResult* result = nil;
	NSString* jsString = nil;
	FileError errCode = 0;  // !! Currently 0 is not defined, use this to signal error !!
		
	if ([arguments count] > 2){
		newName = [arguments objectAtIndex:2];
	} else {
		// use last component from appPath if new name not provided
		newName = [srcFullPath lastPathComponent];
	}
	
	NSString* destRootPath = nil;
	NSString* key = @"fullPath";
	if([options valueForKeyIsString:key]){
	   destRootPath = [options objectForKey:@"fullPath"];
	}
	
	if (!destRootPath) {
		// no destination provided
		errCode = NOT_FOUND_ERR;
	} else if ([newName rangeOfString: @":"].location != NSNotFound) {
		// invalid chars in new name
		errCode = ENCODING_ERR;
	} else {
		NSString* newFullPath = [destRootPath stringByAppendingPathComponent: newName];
		if ( [newFullPath isEqualToString:srcFullPath] ){
			// source and destination can not be the same 
			errCode = INVALID_MODIFICATION_ERR;
		} else {
			NSFileManager* fileMgr = [[NSFileManager alloc] init];
			
			BOOL bSrcIsDir = NO;
			BOOL bDestIsDir = NO;
			BOOL bNewIsDir = NO;
			BOOL bSrcExists = [fileMgr fileExistsAtPath: srcFullPath isDirectory: &bSrcIsDir];
			BOOL bDestExists= [fileMgr fileExistsAtPath: destRootPath isDirectory: &bDestIsDir];
			BOOL bNewExists = [fileMgr fileExistsAtPath:newFullPath isDirectory: &bNewIsDir];
			if (!bSrcExists || !bDestExists) {
				// the source or the destination root does not exist
				errCode = NOT_FOUND_ERR;
			} else if (bSrcIsDir && (bNewExists && !bNewIsDir)) {
				// can't copy/move dir to file 
				errCode = INVALID_MODIFICATION_ERR;
			} else { // no errors yet
				NSError* error = nil;
				BOOL bSuccess = NO;
				if (bCopy){
					if([newFullPath hasPrefix:srcFullPath]) {
						// can't copy into self
						errCode = INVALID_MODIFICATION_ERR;
					}else if (bNewExists) {
						// the full destination should NOT already exist if a copy
						errCode = PATH_EXISTS_ERR;
					}  else {
						bSuccess = [fileMgr copyItemAtPath: srcFullPath toPath: newFullPath error: &error];
					}
				} else { // move 
					// iOS requires that destination must not exist before calling moveTo
					// is W3C INVALID_MODIFICATION_ERR error if destination dir exists and has contents
					// 
					if (!bSrcIsDir && (bNewExists && bNewIsDir)){
						// can't move a file to directory
						errCode = INVALID_MODIFICATION_ERR;
					} else if (bSrcIsDir && [newFullPath hasPrefix:srcFullPath]){
						// can't move a dir into itself
						errCode = INVALID_MODIFICATION_ERR;	
					} else if (bNewExists) {
						if (bNewIsDir && [[fileMgr contentsOfDirectoryAtPath:newFullPath error: NULL] count] != 0){
							// can't move dir to a dir that is not empty
							errCode = INVALID_MODIFICATION_ERR;
							newFullPath = nil;  // so we won't try to move
						} else {
							// remove destination so can perform the moveItemAtPath
							bSuccess = [fileMgr removeItemAtPath:newFullPath error: NULL];
							if (!bSuccess) {
								errCode = INVALID_MODIFICATION_ERR; // is this the correct error?
								newFullPath = nil;
							}
						}
					} else if (bNewIsDir && [newFullPath hasPrefix:srcFullPath]) {
						// can't move a directory inside itself or to any child at any depth;
						errCode = INVALID_MODIFICATION_ERR;
						newFullPath = nil;
					}
						
					if (newFullPath != nil) {
						bSuccess = [fileMgr moveItemAtPath: srcFullPath toPath: newFullPath error: &error];
					}
				}
				if (bSuccess) {
					// should verify it is there and of the correct type???
					NSDictionary* newEntry = [self getDirectoryEntry: newFullPath isDirectory:bSrcIsDir]; //should be the same type as source
					result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsDictionary: newEntry cast: @"window.localFileSystem._castEntry"];
					jsString = [result toSuccessCallbackString:callbackId];
				}
				else {
					errCode = INVALID_MODIFICATION_ERR; // catch all
					if (error) {
						if ([error code] == NSFileReadUnknownError || [error code] == NSFileReadTooLargeError) {
							errCode = NOT_READABLE_ERR;
						} else if ([error code] == NSFileWriteOutOfSpaceError){
							errCode = QUOTA_EXCEEDED_ERR;
						} else if ([error code] == NSFileWriteNoPermissionError){
							errCode = NO_MODIFICATION_ALLOWED_ERR;
						}
					}
				}			
			}
			[fileMgr release];	
		}
	}
	if (errCode > 0) {
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: errCode cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	}
	
	
	if (jsString){
		[self writeJavascript: jsString];
	}
	
}
/* return the URI to the entry
 * IN: 
 * NSArray* arguments
 *	0 - NSString* callbackId
 *	1 - NSString* fullPath of entry
 *	2 - desired mime type of entry - ignored - always returns file://
 */
/*  Not needed since W3C toURI is synchronous.  Leaving code here for now in case W3C spec changes.....
- (void) toURI:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	NSString* fullPath = [self getFullPath: argPath];
	if (fullPath) {
		// do we need to make sure the file actually exists?
		// create file uri
		NSString* strUri = [fullPath stringByReplacingPercentEscapesUsingEncoding: NSUTF8StringEncoding];
		NSURL* fileUrl = [NSURL fileURLWithPath:strUri];
		if (fileUrl) {
			result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsString: [fileUrl absoluteString]];
			jsString = [result toSuccessCallbackString:callbackId];
		} // else NOT_FOUND_ERR
	}
	if(!jsString) {
		// was error
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: NOT_FOUND_ERR cast:  @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	}
	
	[self writeJavascript:jsString];
}*/
- (void) getFileMetadata:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	NSString* fullPath = argPath; //[self getFullPath: argPath];
	if (fullPath) {
		NSFileManager* fileMgr = [[NSFileManager alloc] init];
		BOOL bIsDir = NO;
		// make sure it exists and is not a directory
		BOOL bExists = [fileMgr fileExistsAtPath:fullPath isDirectory: &bIsDir];
		if(!bExists || bIsDir){
			result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: NOT_FOUND_ERR cast:@"window.localFileSystem._castError"];
			jsString = [result toErrorCallbackString:callbackId];
		} else {
			// create dictionary of file info
			NSError* error = nil;
			NSDictionary* fileAttrs = [fileMgr attributesOfItemAtPath:fullPath error:&error];
			NSMutableDictionary* fileInfo = [NSMutableDictionary dictionaryWithCapacity:5];
			[fileInfo setObject: [NSNumber numberWithUnsignedLongLong:[fileAttrs fileSize]] forKey:@"size"];
			[fileInfo setObject:argPath forKey:@"fullPath"];
			[fileInfo setObject: @"" forKey:@"type"]; // can't easily get the mimetype unless create URL, send request and read response so skipping
			[fileInfo setObject: [argPath lastPathComponent] forKey:@"name"];
			NSDate* modDate = [fileAttrs fileModificationDate];
			NSNumber* msDate = [NSNumber numberWithDouble:[modDate timeIntervalSince1970]*1000];
			[fileInfo setObject:msDate forKey:@"lastModifiedDate"];
			result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsDictionary: fileInfo cast: @"window.localFileSystem._castDate"];
			jsString = [result toSuccessCallbackString:callbackId];
		}
		[fileMgr release];
	}
	
	[self writeJavascript:jsString];
}
- (void) readEntries:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* fullPath = [arguments objectAtIndex:1];
	
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	NSFileManager* fileMgr = [[ NSFileManager alloc] init];
	NSError* error = nil;
	NSArray* contents = [fileMgr contentsOfDirectoryAtPath:fullPath error: &error];
	if (contents) {
		NSMutableArray* entries = [NSMutableArray arrayWithCapacity:1];
		if ([contents count] > 0){
			// create an Entry (as JSON) for each file/dir
			for (NSString* name in contents) {
				// see if is dir or file
				NSString* entryPath = [fullPath stringByAppendingPathComponent:name];
				BOOL bIsDir = NO;
				[fileMgr fileExistsAtPath:entryPath isDirectory: &bIsDir];
				NSDictionary* entryDict = [self getDirectoryEntry:entryPath isDirectory:bIsDir];
				[entries addObject:[entryDict JSONRepresentation]];
			}
		}
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsArray: entries cast: @"window.localFileSystem._castEntries"];
		jsString = [result toSuccessCallbackString:callbackId];
	} else {
		// assume not found but could check error for more specific error conditions
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: NOT_FOUND_ERR cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	} 

	[fileMgr release];
	
	[self writeJavascript: jsString];
	
}
/* read and return file data 
 * IN: 
 * NSArray* arguments
 *	0 - NSString* callbackId
 *	1 - NSString* fullPath
 *	2 - NSString* encoding - NOT USED,  iOS reads and writes using UTF8!
 * NSMutableDictionary* options
 *	empty
 */
- (void) readFile:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	//NSString* encoding = [arguments objectAtIndex:2];   // not currently used
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	NSString *filePath = argPath; //[ self getFullPath: argPath];
	
	if(!filePath){
		// invalid path entry
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: NOT_FOUND_ERR cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	} else {
		NSFileHandle* file = [ NSFileHandle fileHandleForReadingAtPath:filePath];
		
		NSData* readData = [ file readDataToEndOfFile];
		
		[file closeFile];
		
		NSString* pNStrBuff = [[NSString alloc] initWithBytes: [readData bytes] length: [readData length] encoding: NSUTF8StringEncoding];
		
		result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsString: [ pNStrBuff stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] ];
		jsString = [result toSuccessCallbackString:callbackId];
		[ pNStrBuff release ];
		
	}
	if (jsString){
		[self writeJavascript: jsString];
	}
	

}
/* Read content of text file and return as base64 encoded data url.
 * IN: 
 * NSArray* arguments
 *	0 - NSString* callbackId
 *	1 - NSString* fullPath
 * NSMutableDictionary* options
 *	empty
 * 
 * Determines the mime type from the file extension, returns ENCODING_ERR if mimetype can not be determined. 
 */
 
- (void) readAsDataURL:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	FileError errCode = ABORT_ERR; 
	
	PluginResult* result = nil;
	NSString* jsString = nil;
	
	if(!argPath){
		errCode = SYNTAX_ERR;
	} else {
		NSString* mimeType = [self getMimeTypeFromPath:argPath];
		if (!mimeType) {
			// can't return as data URL if can't figure out the mimeType
			errCode = ENCODING_ERR;
		} else {
			NSFileHandle* file = [ NSFileHandle fileHandleForReadingAtPath:argPath];
			NSData* readData = [ file readDataToEndOfFile];
			[file closeFile];
			if (readData) {
				NSString* output = [NSString stringWithFormat:@"data:%@;base64,%@", mimeType, [readData base64EncodedString]];
				result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsString: output];
				jsString = [result toSuccessCallbackString:callbackId];
			} else {
				errCode = NOT_FOUND_ERR;
			}
		}
	}
	if (!jsString){
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: errCode cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	}
	//NSLog(@"readAsDataURL return: %@", jsString);
	[self writeJavascript:jsString];
		
	
}
/* helper function to get the mimeType from the file extension
 * IN:
 *	NSString* fullPath - filename (may include path)
 * OUT:
 *	NSString* the mime type as type/subtype.  nil if not able to determine
 */
-(NSString*) getMimeTypeFromPath: (NSString*) fullPath
{	
	
	NSString* mimeType = nil;
	if(fullPath) {
		CFStringRef typeId = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension,(CFStringRef)[fullPath pathExtension], NULL);
		if (typeId) {
			mimeType = (NSString*)UTTypeCopyPreferredTagWithClass(typeId,kUTTagClassMIMEType);
			if (mimeType) {
				[mimeType autorelease];
				//NSLog(@"mime type: %@", mimeType);
			}
			CFRelease(typeId);
		}
	}
	return mimeType;
}

- (void) truncateFile:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	
	unsigned long long pos = (unsigned long long)[[arguments objectAtIndex:2 ] longLongValue];
	
	NSString *appFile = argPath; //[self getFullPath:argPath];
	
	unsigned long long newPos = [ self truncateFile:appFile atPosition:pos];
	PluginResult* result = [PluginResult resultWithStatus: PGCommandStatus_OK messageAsInt: newPos];
	[self writeJavascript:[result toSuccessCallbackString: callbackId]];
	 
}

- (unsigned long long) truncateFile:(NSString*)filePath atPosition:(unsigned long long)pos
{

	unsigned long long newPos = 0UL;
	
	NSFileHandle* file = [ NSFileHandle fileHandleForWritingAtPath:filePath];
	if(file)
	{
		[file truncateFileAtOffset:(unsigned long long)pos];
		newPos = [ file offsetInFile];
		[ file synchronizeFile];
		[ file closeFile];
	}
	return newPos;
} 
/* writeAsText  - deprecated
 * IN:
 * NSArray* arguments
 *  0 - NSString* callbackId
 *  1 - NSString* file path to write to
 *  2 - NSString* data to write
 *  3 - NSNumber* 1 to append to file, 0 to overwrite
 */
- (void) writeAsText:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	NSString* argData = [arguments objectAtIndex:2];
	BOOL bAppend = [[arguments objectAtIndex:3] boolValue];
	
	//[self writeToFile:[self getFullPath:argPath] withData:argData append: bAppend callback: callbackId];
	[self writeToFile:argPath withData:argData append: bAppend callback: callbackId];
	
}
/* writeAsText  - deprecated
 * IN:
 * NSArray* arguments
 *  0 - NSString* callbackId
 *  1 - NSString* file path to write to
 *  2 - NSString* data to write
 *  3 - NSNumber* position to begin writing 
 */
- (void) write:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	NSString* argData = [arguments objectAtIndex:2];
	unsigned long long pos = (unsigned long long)[[ arguments objectAtIndex:3] longLongValue];
	
	NSString* fullPath = argPath; //[self getFullPath:argPath];
	
	[self truncateFile:fullPath atPosition:pos];
	
	[self writeToFile: fullPath withData:argData append:YES callback: callbackId];
}
- (void) writeToFile:(NSString*)filePath withData:(NSString*)data append:(BOOL)shouldAppend callback: (NSString*) callbackId
{	
	PluginResult* result = nil;
	NSString* jsString = nil;
	FileError errCode = INVALID_MODIFICATION_ERR; 
	int bytesWritten = 0;
	NSData* encData = [ data dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES];
	if (filePath) {
		NSOutputStream* fileStream = [NSOutputStream outputStreamToFileAtPath:filePath append:shouldAppend ];
		if (fileStream) {
			NSUInteger len = [ encData length ];
			[ fileStream open ];
			
			bytesWritten = [ fileStream write:[encData bytes] maxLength:len];
			
			[ fileStream close ];
			if (bytesWritten > 0) {
				result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: bytesWritten];
				jsString = [result toSuccessCallbackString:callbackId];
			//} else {
				// can probably get more detailed error info via [fileStream streamError]
				//errCode already set to INVALID_MODIFICATION_ERR;
				//bytesWritten = 0; // may be set to -1 on error
			}
		} // else fileStream not created return INVALID_MODIFICATION_ERR
	} else {
		// invalid filePath
		errCode = NOT_FOUND_ERR;
	}
	if(!jsString) {
		// was an error 
		result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: errCode cast: @"window.localFileSystem._castError"];
		jsString = [result toErrorCallbackString:callbackId];
	}
	[self writeJavascript: jsString];
	
}

- (void) testFileExists:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	NSString* jsString = nil;
	// Get the file manager
	NSFileManager* fMgr = [ NSFileManager defaultManager ];
	NSString *appFile = argPath; //[ self getFullPath: argPath];
	
	BOOL bExists = [fMgr fileExistsAtPath:appFile];
	PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: ( bExists ? 1 : 0 )];
	// keep original format of returning 0 or 1 to success  callback
	jsString = [result toSuccessCallbackString: callbackId];
	

	[self writeJavascript: jsString];
}

- (void) testDirectoryExists:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSString* argPath = [arguments objectAtIndex:1];
	
	NSString* jsString = nil;
	// Get the file manager
	NSFileManager* fMgr = [[NSFileManager alloc] init];
	NSString *appFile = argPath; //[self getFullPath: argPath];
	BOOL bIsDir = NO;
	BOOL bExists = [fMgr fileExistsAtPath:appFile isDirectory: &bIsDir];
	
	
	PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsInt: ( (bExists && bIsDir) ? 1 : 0 )];
	// keep original format of returning 0 or 1 to success callback
	jsString = [result toSuccessCallbackString: callbackId];
	[fMgr release];
	[self writeJavascript: jsString];
}

// Returns number of bytes available via callback
- (void) getFreeDiskSpace:(NSMutableArray*)arguments withDict:(NSMutableDictionary*)options
{
	NSString* callbackId = [arguments objectAtIndex:0];
	NSNumber* pNumAvail = [self checkFreeDiskSpace:self.appDocsPath];
	
	NSString* strFreeSpace = [NSString stringWithFormat:@"%qu", [ pNumAvail unsignedLongLongValue ] ];
	//NSLog(@"Free space is %@", strFreeSpace );
	
	PluginResult* result = [PluginResult resultWithStatus:PGCommandStatus_OK messageAsString: strFreeSpace];
	[self writeJavascript:[result toSuccessCallbackString: callbackId]];
	
}

-(void) dealloc
{
	self.appDocsPath = nil;
	self.appLibraryPath = nil;
	self.appTempPath = nil;
	self.persistentPath = nil;
	self.temporaryPath = nil;
	
	[super dealloc];
}





@end
