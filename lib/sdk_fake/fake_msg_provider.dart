import 'dart:async';
import 'dart:io';
import 'package:tencent_cloud_chat_common/external/chat_message_provider.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/tencent_cloud_chat_intl.dart';
import 'package:tencent_cloud_chat_common/data/message/tencent_cloud_chat_message_data.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_message.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_text_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_custom_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_image.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_file_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_video_elem.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_sound_elem.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_elem_type.dart';
import 'package:tencent_cloud_chat_sdk/enum/image_types.dart';
import 'package:tencent_cloud_chat_sdk/enum/message_status.dart';
import 'package:tim2tox_dart/utils/tim2tox_failed_message_persistence.dart';
import '../sdk_fake/fake_uikit_core.dart';
import '../sdk_fake/fake_im.dart';
import '../sdk_fake/fake_models.dart';
import '../util/prefs.dart';
import '../util/tox_utils.dart';
import '../util/logger.dart';

class FakeChatMessageProvider implements ChatMessageProvider {
  final Map<String, StreamController<List<V2TimMessage>>> _ctrls = {};
  final Map<String, List<V2TimMessage>> _buffers = {};
  StreamSubscription? _sub;
  String? _cachedSelfAvatarPath; // Cache self avatar path to avoid async calls
  final Map<String, String?> _cachedFriendAvatars = {}; // Cache friend avatar paths
  // Track file receive progress: msgID -> (received, total, path)
  final Map<String, ({int received, int total, String? path})> _fileProgress = {};

  FakeChatMessageProvider() {
    // Load self avatar path on initialization
    Prefs.getAvatarPath().then((path) {
      _cachedSelfAvatarPath = path;
    });
    // Listen for message data updates to sync deletions
    _listenForMessageDeletions();
    // Listen to file transfer progress updates from FfiChatService
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi != null) {
      ffi.progressUpdates.listen((progress) {
        if (!progress.isSend && progress.path != null) {
          // File receiving progress
          // CRITICAL: Prioritize msgID matching to avoid fileNumber reuse issues
          // Find the message by msgID first (most reliable), then fall back to path matching
          V2TimMessage? matchedMsg;
          String? matchedConvID;
          
          // Priority 1: Match by msgID if available (most reliable, avoids fileNumber conflicts)
          if (progress.msgID != null && progress.msgID!.isNotEmpty) {
            for (final entry in _buffers.entries) {
              final convID = entry.key;
              final messages = entry.value;
              try {
                final foundMsg = messages.firstWhere((msg) => msg.msgID == progress.msgID);
                // CRITICAL: Create a copy of the message to avoid modifying the original in _buffers
                // This ensures we work with the latest state from _buffers
                matchedMsg = foundMsg;
                matchedConvID = convID;
                // Skip logging match details - too frequent during file transfer
                break;
              } catch (_) {
                // msgID not found in this conversation, continue
              }
            }
            if (matchedMsg == null) {
              // CRITICAL: If msgID is provided but not found, don't fall back to path matching
              // This prevents fileNumber reuse from causing false matches when msgID is stale
              // The message may have been removed or the progress update is for a different file
              AppLogger.log('[FakeMessageProvider] ⚠️ msgID=${progress.msgID} not found in any conversation, ignoring progress update to prevent false matches');
              return; // Skip this progress update
            }
          } else {
            AppLogger.log('[FakeMessageProvider] ⚠️ progress.msgID is null or empty, will use path matching');
          }
          
          // Priority 2: Fall back to path/filename matching ONLY if msgID was not provided
          // If msgID was provided but not found, we already returned above
          if (matchedMsg == null) {
            // CRITICAL: Extract actual filename, not the full path with fileNumber
            // Path format: .../file_recv/{uid}_{fileKind}_{fileNumber}_{originalFileName}
            // or: /tmp/receiving_{originalFileName}
            String? extractActualFileName(String? path) {
              if (path == null) return null;
              final basename = path.split('/').last;
              // Check if it's a temp path (starts with "receiving_")
              if (basename.startsWith('receiving_')) {
                return basename.substring('receiving_'.length);
              }
              // Check if it's a file_recv path with fileNumber (format: {uid}_{fileKind}_{fileNumber}_{originalFileName})
              if (basename.contains('_') && basename.length > 64) {
                final parts = basename.split('_');
                if (parts.length >= 4) {
                  // Extract original filename (everything after the first 3 parts)
                  return parts.sublist(3).join('_');
                }
              }
              // Otherwise, use basename as-is
              return basename;
            }
            
            final progressFileName = extractActualFileName(progress.path);
            
            for (final entry in _buffers.entries) {
              final convID = entry.key;
              final messages = entry.value;
              for (final msg in messages) {
                final msgFilePath = msg.fileElem?.path ?? msg.imageElem?.path ?? msg.videoElem?.videoPath ?? msg.soundElem?.path;
                final msgFileName = extractActualFileName(msgFilePath);
                // Remove "receiving_" prefix from temp path filename for matching (already handled in extractActualFileName)
                final msgFileNameWithoutPrefix = msgFileName;
                
                // Match by path (temp path or actual path), filename, or by checking if it's a pending file message
                // Check fileElem, imageElem, videoElem, and soundElem messages
                // Note: New message ID format is timestamp_userID (no file_recv_ prefix)
                // CRITICAL: Prioritize exact path matching, then filename matching
                // IMPORTANT: Only match pending files (no localUrl) to avoid matching completed files
                // This prevents fileNumber reuse from causing completed files to show as receiving
                // CRITICAL: Even for exact path match, skip completed files to prevent false matches when fileNumber is reused
                final isFilePending = msg.fileElem != null && 
                    (msg.fileElem!.localUrl == null || msg.fileElem!.localUrl!.isEmpty);
                final isImagePending = msg.imageElem != null && 
                    (msg.imageElem!.imageList == null || msg.imageElem!.imageList!.isEmpty || 
                     msg.imageElem!.imageList!.every((img) => img == null || img.localUrl == null || img.localUrl!.isEmpty));
                final isVideoPending = msg.videoElem != null &&
                    (msg.videoElem!.localVideoUrl == null || msg.videoElem!.localVideoUrl!.isEmpty);
                final isAudioPending = msg.soundElem != null &&
                    (msg.soundElem!.localUrl == null || msg.soundElem!.localUrl!.isEmpty);
                final isFileMatch = msg.fileElem != null && (
                  // Exact path match (highest priority) - but only if file is pending
                  (isFilePending && msg.fileElem!.path == progress.path) ||
                  // Filename match only if file is still pending (no localUrl)
                  (isFilePending &&
                   (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
                  // Filename match (fallback, but only if file is pending)
                  (isFilePending &&
                   (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
                );
                final isImageMatch = msg.imageElem != null && (
                  // Exact path match (highest priority) - but only if image is pending
                  (isImagePending && msg.imageElem!.path == progress.path) ||
                  // Filename match only if image is still pending (no localUrl in imageList)
                  (isImagePending &&
                   (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
                  // Filename match (fallback, but only if image is pending)
                  (isImagePending &&
                   (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
                );
                final isVideoMatch = msg.videoElem != null && (
                  (isVideoPending && msg.videoElem!.videoPath == progress.path) ||
                  (isVideoPending &&
                   (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
                  (isVideoPending &&
                   (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
                );
                final isAudioMatch = msg.soundElem != null && (
                  (isAudioPending && msg.soundElem!.path == progress.path) ||
                  (isAudioPending &&
                   (progressFileName != null && msgFileNameWithoutPrefix != null && progressFileName == msgFileNameWithoutPrefix)) ||
                  (isAudioPending &&
                   (progressFileName != null && msgFileName != null && progressFileName == msgFileName))
                );
                if (isFileMatch || isImageMatch || isVideoMatch || isAudioMatch) {
                  matchedMsg = msg;
                  matchedConvID = convID;
                  // Skip logging match details - too frequent during file transfer
                  break;
                }
              }
              if (matchedMsg != null) {
                break;
              }
            }
          }
          
          if (matchedMsg != null && matchedConvID != null) {
            // Update progress for this message
            final msgID = matchedMsg.msgID ?? '';
            if (msgID.isNotEmpty) {
              // CRITICAL: Re-fetch the message from _buffers to ensure we have the latest state
              // This is necessary because _buffers may have been updated by a previous progress update
              // or by a file_done event, and matchedMsg may still reference the old object
              if (_buffers.containsKey(matchedConvID)) {
                try {
                  final latestMsg = _buffers[matchedConvID]!.firstWhere((msg) => msg.msgID == msgID);
                  final oldPath = matchedMsg?.imageElem?.path ?? matchedMsg?.fileElem?.path;
                  final newPath = latestMsg.imageElem?.path ?? latestMsg.fileElem?.path;
                  final oldLocalUrl = matchedMsg?.imageElem?.imageList?.cast<V2TimImage?>().firstWhere((img) => img?.localUrl != null, orElse: () => null)?.localUrl ?? matchedMsg?.fileElem?.localUrl;
                  final newLocalUrl = latestMsg.imageElem?.imageList?.cast<V2TimImage?>().firstWhere((img) => img?.localUrl != null, orElse: () => null)?.localUrl ?? latestMsg.fileElem?.localUrl;
                  // Skip logging re-fetch details - too frequent during file transfer
                  matchedMsg = latestMsg; // Update matchedMsg to reference the latest state
                } catch (_) {
                  // Message not found in _buffers, use original matchedMsg
                  AppLogger.log('[FakeMessageProvider] ⚠️ Message not found in _buffers after re-fetch: msgID=$msgID, conv=$matchedConvID');
                }
              }
              
              // Ensure matchedMsg is not null after re-fetch
              if (matchedMsg == null) return;
              
              // CRITICAL: Check if file is already complete before processing progress update
              // If file is already complete (has localUrl or path in file_recv/avatars, not in /tmp/receiving_),
              // ignore subsequent progress updates to prevent re-adding to _fileProgress
              // This prevents completed files from showing spinning state when delayed progress_recv events arrive
              // IMPORTANT: Also check progress.received >= progress.total to ensure we don't ignore updates for files still receiving
              final receivedLessThanTotal = progress.received < progress.total && progress.total > 0;
              final hasLocalUrl = (matchedMsg.fileElem != null && matchedMsg.fileElem!.localUrl != null && matchedMsg.fileElem!.localUrl!.isNotEmpty) ||
                                  (matchedMsg.imageElem != null && matchedMsg.imageElem!.imageList?.any((img) => 
                                    img != null && img.localUrl != null && img.localUrl!.isNotEmpty
                                  ) == true) ||
                                  (matchedMsg.videoElem != null && matchedMsg.videoElem!.localVideoUrl != null && matchedMsg.videoElem!.localVideoUrl!.isNotEmpty) ||
                                  (matchedMsg.soundElem != null && matchedMsg.soundElem!.localUrl != null && matchedMsg.soundElem!.localUrl!.isNotEmpty);
              final hasFinalPath = (matchedMsg.fileElem != null && matchedMsg.fileElem!.path != null && (
                                    matchedMsg.fileElem!.path!.contains('/file_recv/') ||
                                    matchedMsg.fileElem!.path!.contains('/avatars/')
                                  )) ||
                                  (matchedMsg.imageElem != null && matchedMsg.imageElem!.path != null && (
                                    matchedMsg.imageElem!.path!.contains('/file_recv/') ||
                                    matchedMsg.imageElem!.path!.contains('/avatars/')
                                  )) ||
                                  (matchedMsg.videoElem != null && matchedMsg.videoElem!.videoPath != null && (
                                    matchedMsg.videoElem!.videoPath!.contains('/file_recv/') ||
                                    matchedMsg.videoElem!.videoPath!.contains('/avatars/')
                                  )) ||
                                  (matchedMsg.soundElem != null && matchedMsg.soundElem!.path != null && (
                                    matchedMsg.soundElem!.path!.contains('/file_recv/') ||
                                    matchedMsg.soundElem!.path!.contains('/avatars/')
                                  ));
              
              // CRITICAL: Check isPending status - if message is not pending, it's already complete
              // This is the most reliable indicator that the file transfer is complete
              // Pending status is stored in customElem.data as '{"isPending":true}'
              final customData = matchedMsg.customElem?.data;
              final isPending = customData != null && customData.contains('"isPending":true');
              final isNotPending = !isPending;
              
              final isAlreadyComplete = (
                // First check: If message is not pending, it's already complete (most reliable)
                isNotPending ||
                // Second check: File has localUrl (definitive completion indicator)
                hasLocalUrl ||
                // Third check: File path is in final location (and not in /tmp/receiving_)
                (hasFinalPath && !receivedLessThanTotal)
              );
              
              if (isAlreadyComplete) {
                // File is already complete, ignore this progress update to prevent re-adding to _fileProgress
                // CRITICAL: Also remove from _fileProgress if it exists, to prevent UI from showing spinning state
                final hadProgress = _fileProgress.containsKey(msgID);
                if (hadProgress) {
                  final oldProgress = _fileProgress[msgID];
                  _fileProgress.remove(msgID);
                  AppLogger.log('[FakeMessageProvider] ⚠️ File already complete, removed from _fileProgress for msgID=$msgID (old progress: ${oldProgress?.received}/${oldProgress?.total})');
                } else {
                  AppLogger.log('[FakeMessageProvider] File already complete, ignoring progress update for msgID=$msgID (no _fileProgress entry)');
                }
                // Skip processing this progress update - don't update _fileProgress or message elements
                // This prevents completed files from showing spinning state when delayed progress_recv events arrive
              } else {
                // CRITICAL: Clear progress when file is complete to prevent UI from showing spinning state
                // If file is complete (received >= total), remove from _fileProgress so UI knows it's done
                final isComplete = progress.received >= progress.total && progress.total > 0;
                if (isComplete) {
                  final hadProgress = _fileProgress.containsKey(msgID);
                  _fileProgress.remove(msgID);
                  AppLogger.log('[FakeMessageProvider] ✅ File complete, cleared progress for msgID=$msgID (hadProgress=$hadProgress)');
                } else {
                  final oldProgress = _fileProgress[msgID];
                  _fileProgress[msgID] = (
                    received: progress.received,
                    total: progress.total,
                    path: progress.path,
                  );
                  // Skip logging progress updates - too frequent during file transfer
                }
                // Update file element path if it's still using temp path
                if (matchedMsg.fileElem != null && matchedMsg.fileElem!.path?.startsWith('/tmp/receiving_') == true && progress.path != null) {
                // Recreate the file element with updated path and localUrl to ensure widget updates
                final oldFileElem = matchedMsg.fileElem!;
                final isComplete = progress.received >= progress.total && progress.total > 0;
                final newLocalUrl = isComplete ? progress.path : oldFileElem.localUrl;
                // CRITICAL: Don't use /tmp/receiving_ paths as URL
                final newFileUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldFileElem.url;
                // CRITICAL: Only update path if file is complete, otherwise keep temp path to prevent isAlreadyComplete from returning true prematurely
                final newPath = isComplete ? progress.path : oldFileElem.path;
                matchedMsg.fileElem = V2TimFileElem(
                  path: newPath, // CRITICAL: Only update path if file is complete, otherwise keep temp path
                  fileName: oldFileElem.fileName,
                  fileSize: oldFileElem.fileSize ?? progress.total,
                  UUID: oldFileElem.UUID,
                  url: newFileUrl,
                  localUrl: newLocalUrl,
                );
                // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
                if (_buffers.containsKey(matchedConvID!)) {
                  final bufferList = _buffers[matchedConvID]!;
                  final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                  if (bufferIndex >= 0) {
                    bufferList[bufferIndex] = matchedMsg;
                    // Skip logging buffer updates - too frequent during file transfer
                  }
                }
                // Skip logging fileElem updates - too frequent during file transfer
                } else if (matchedMsg.fileElem != null && progress.received >= progress.total && progress.total > 0) {
                  // File is complete, update localUrl even if path wasn't temp
                  final oldFileElem = matchedMsg.fileElem!;
                  if (oldFileElem.localUrl == null || oldFileElem.localUrl!.isEmpty) {
                    // CRITICAL: Don't use /tmp/receiving_ paths as URL
                    final newFileUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldFileElem.url;
                    matchedMsg.fileElem = V2TimFileElem(
                      path: oldFileElem.path ?? progress.path,
                      fileName: oldFileElem.fileName,
                      fileSize: oldFileElem.fileSize ?? progress.total,
                      UUID: oldFileElem.UUID,
                      url: newFileUrl,
                      localUrl: progress.path,
                    );
                    // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
                    if (_buffers.containsKey(matchedConvID!)) {
                      final bufferList = _buffers[matchedConvID]!;
                      final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                      if (bufferIndex >= 0) {
                        bufferList[bufferIndex] = matchedMsg;
                        // Skip logging buffer updates - too frequent during file transfer
                      }
                    }
                  }
                }
                // Update image element if it's still using temp path
                if (matchedMsg.imageElem != null && matchedMsg.imageElem!.path?.startsWith('/tmp/receiving_') == true && progress.path != null) {
                // Update imageElem path and create/update imageList with localUrl
                final oldImageElem = matchedMsg.imageElem!;
                final isComplete = progress.received >= progress.total && progress.total > 0;
                final newLocalUrl = isComplete ? progress.path : null;
                // CRITICAL: Don't use /tmp/receiving_ paths as URL
                final newImageUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : null;
                // CRITICAL: Only update path if file is complete, otherwise keep temp path to prevent isAlreadyComplete from returning true prematurely
                final newPath = isComplete ? progress.path : oldImageElem.path;
                // Create imageList with localUrl if file is complete
                final imageList = <V2TimImage?>[];
                if (newLocalUrl != null) {
                  final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
                  thumbImage.localUrl = newLocalUrl;
                  if (newImageUrl != null) {
                    thumbImage.url = newImageUrl;
                  }
                  // Preserve UUID if it exists
                  if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                    final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB, orElse: () => null);
                    if (oldImg?.uuid != null) {
                      thumbImage.uuid = oldImg!.uuid;
                    }
                  }
                  imageList.add(thumbImage);
                  final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
                  originImage.localUrl = newLocalUrl;
                  if (newImageUrl != null) {
                    originImage.url = newImageUrl;
                  }
                  // Preserve UUID if it exists
                  if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                    final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN, orElse: () => null);
                    if (oldImg?.uuid != null) {
                      originImage.uuid = oldImg!.uuid;
                    }
                  }
                  imageList.add(originImage);
                } else {
                  // File is still receiving, but update imageList to remove temp path URLs
                  // Preserve existing imageList structure but filter out temp path URLs
                  if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                    for (final oldImg in oldImageElem.imageList!) {
                      if (oldImg != null) {
                        final newImg = V2TimImage(type: oldImg.type);
                        newImg.uuid = oldImg.uuid;
                        newImg.localUrl = oldImg.localUrl;
                        // CRITICAL: Don't preserve /tmp/receiving_ paths as URL
                        if (oldImg.url != null && !oldImg.url!.startsWith('/tmp/receiving_')) {
                          newImg.url = oldImg.url;
                        }
                        // If url was a temp path but newImageUrl is available, use it
                        else if (newImageUrl != null) {
                          newImg.url = newImageUrl;
                        }
                        newImg.width = oldImg.width;
                        newImg.height = oldImg.height;
                        newImg.size = oldImg.size;
                        imageList.add(newImg);
                      }
                    }
                  }
                }
                // CRITICAL: If imageList is empty, filter oldImageElem.imageList to remove temp path URLs
                final finalImageList = imageList.isNotEmpty 
                    ? imageList 
                    : (oldImageElem.imageList != null 
                        ? oldImageElem.imageList!.map((img) {
                            if (img == null) return null;
                            final newImg = V2TimImage(type: img.type);
                            newImg.uuid = img.uuid;
                            newImg.localUrl = img.localUrl;
                            // CRITICAL: Don't preserve /tmp/receiving_ paths as URL
                            if (img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                              newImg.url = img.url;
                            }
                            // If url was a temp path but localUrl is available and not a temp path, use localUrl as url
                            else if (img.localUrl != null && !img.localUrl!.startsWith('/tmp/receiving_')) {
                              newImg.url = img.localUrl;
                            }
                            newImg.width = img.width;
                            newImg.height = img.height;
                            newImg.size = img.size;
                            return newImg;
                          }).toList()
                        : null);
                  matchedMsg.imageElem = V2TimImageElem(
                    path: newPath, // CRITICAL: Only update path if file is complete, otherwise keep temp path
                    imageList: finalImageList,
                  );
                  // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
                  if (_buffers.containsKey(matchedConvID!)) {
                    final bufferList = _buffers[matchedConvID]!;
                    final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                    if (bufferIndex >= 0) {
                      bufferList[bufferIndex] = matchedMsg;
                      // Skip logging buffer updates - too frequent during file transfer
                    }
                  }
                  // Skip logging imageElem updates - too frequent during file transfer
                } else if (matchedMsg.imageElem != null && progress.received >= progress.total && progress.total > 0) {
                // Image is complete, update imageList with localUrl even if path wasn't temp
                final oldImageElem = matchedMsg.imageElem!;
                // Check if imageList already has localUrl
                bool hasLocalUrl = false;
                if (oldImageElem.imageList != null) {
                  for (final img in oldImageElem.imageList!) {
                    if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                      hasLocalUrl = true;
                      break;
                    }
                  }
                }
                AppLogger.log('[FakeMessageProvider] Image complete: msgID=$msgID, hasLocalUrl=$hasLocalUrl, progress.path=${progress.path}, oldImageElem.path=${oldImageElem.path}');
                if (!hasLocalUrl && progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
                  // Create imageList with localUrl
                  AppLogger.log('[FakeMessageProvider] Creating imageList with localUrl for completed image: msgID=$msgID, localUrl=${progress.path}');
                  final imageList = <V2TimImage?>[];
                  final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
                  thumbImage.localUrl = progress.path;
                  thumbImage.url = progress.path; // Use valid path as URL
                  // Preserve UUID if it exists
                  if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                    final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB, orElse: () => null);
                    if (oldImg?.uuid != null) {
                      thumbImage.uuid = oldImg!.uuid;
                    }
                  }
                  imageList.add(thumbImage);
                  final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
                  originImage.localUrl = progress.path;
                  originImage.url = progress.path; // Use valid path as URL
                  // Preserve UUID if it exists
                  if (oldImageElem.imageList != null && oldImageElem.imageList!.isNotEmpty) {
                    final oldImg = oldImageElem.imageList!.cast<V2TimImage?>().firstWhere((img) => img?.type == V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN, orElse: () => null);
                    if (oldImg?.uuid != null) {
                      originImage.uuid = oldImg!.uuid;
                    }
                  }
                  imageList.add(originImage);
                  matchedMsg.imageElem = V2TimImageElem(
                    path: oldImageElem.path ?? progress.path,
                    imageList: imageList,
                  );
                  // CRITICAL: Update the message in _buffers to ensure subsequent progress updates see the updated path/localUrl
                  if (_buffers.containsKey(matchedConvID!)) {
                    final bufferList = _buffers[matchedConvID]!;
                    final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                    if (bufferIndex >= 0) {
                      bufferList[bufferIndex] = matchedMsg;
                      // Skip logging buffer updates - too frequent during file transfer
                    }
                  }
                  // Skip logging imageElem updates - too frequent during file transfer
                } else {
                  AppLogger.log('[FakeMessageProvider] ⚠️ Image complete but hasLocalUrl=$hasLocalUrl or progress.path is null/temp: msgID=$msgID, progress.path=${progress.path}');
                }
                }
                // Update video element path if it's still using temp path or is complete
                if (matchedMsg.videoElem != null) {
                  final oldVideoElem = matchedMsg.videoElem!;
                  final isComplete = progress.received >= progress.total && progress.total > 0;
                  final newLocalVideoUrl = isComplete ? progress.path : oldVideoElem.localVideoUrl;
                  final newVideoUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldVideoElem.videoUrl;
                  final newVideoPath = isComplete ? (progress.path ?? oldVideoElem.videoPath) : oldVideoElem.videoPath;
                  matchedMsg.videoElem = V2TimVideoElem(
                    videoPath: newVideoPath,
                    UUID: oldVideoElem.UUID,
                    videoSize: oldVideoElem.videoSize ?? progress.total,
                    duration: oldVideoElem.duration,
                    videoUrl: newVideoUrl,
                    localVideoUrl: newLocalVideoUrl,
                    snapshotPath: oldVideoElem.snapshotPath,
                    snapshotUUID: oldVideoElem.snapshotUUID,
                    snapshotUrl: oldVideoElem.snapshotUrl,
                    localSnapshotUrl: oldVideoElem.localSnapshotUrl,
                  );
                  if (_buffers.containsKey(matchedConvID!)) {
                    final bufferList = _buffers[matchedConvID]!;
                    final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                    if (bufferIndex >= 0) {
                      bufferList[bufferIndex] = matchedMsg;
                    }
                  }
                }
                // Update sound element path if it's still using temp path or is complete
                if (matchedMsg.soundElem != null) {
                  final oldSoundElem = matchedMsg.soundElem!;
                  final isComplete = progress.received >= progress.total && progress.total > 0;
                  final newLocalUrl = isComplete ? progress.path : oldSoundElem.localUrl;
                  final newUrl = (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) ? progress.path : oldSoundElem.url;
                  final newPath = isComplete ? (progress.path ?? oldSoundElem.path) : oldSoundElem.path;
                  matchedMsg.soundElem = V2TimSoundElem(
                    path: newPath,
                    UUID: oldSoundElem.UUID,
                    dataSize: oldSoundElem.dataSize ?? progress.total,
                    duration: oldSoundElem.duration,
                    url: newUrl,
                    localUrl: newLocalUrl,
                  );
                  if (_buffers.containsKey(matchedConvID!)) {
                    final bufferList = _buffers[matchedConvID]!;
                    final bufferIndex = bufferList.indexWhere((m) => m.msgID == msgID);
                    if (bufferIndex >= 0) {
                      bufferList[bufferIndex] = matchedMsg;
                    }
                  }
                }
                // Trigger stream update to refresh UI
                final messages = _buffers[matchedConvID]!;
                final reversedList = List<V2TimMessage>.from(messages.reversed);
                _ctrls[matchedConvID]?.add(reversedList);
              }
            }
          }
        }
      });
      // When a friend's avatar is received and saved, invalidate our in-memory cache
      // and re-emit the stream for their conversation so message bubbles update immediately.
      ffi.avatarUpdated.listen((uid) async {
        _cachedFriendAvatars.remove(uid);
        final newPath = await Prefs.getFriendAvatarPath(uid);
        _cachedFriendAvatars[uid] = newPath ?? '';
        final convId = 'c2c_$uid';
        if (_buffers.containsKey(convId) && _ctrls.containsKey(convId)) {
          final msgs = _buffers[convId]!;
          for (final msg in msgs) {
            if (msg.isSelf != true) {
              msg.faceUrl = newPath?.isNotEmpty == true ? newPath : null;
            }
          }
          _ctrls[convId]?.add(List<V2TimMessage>.from(msgs.reversed));
        }
      });
    }
    _sub = FakeUIKit.instance.eventBusInstance.on<FakeMessage>(FakeIM.topicMessage).listen((m) async {
      final conv = m.conversationID;
      AppLogger.log('[FakeMessageProvider] EventBus received: msgID=${m.msgID}, conv=$conv, mediaKind=${m.mediaKind}, fromUser=${m.fromUser}');
      final list = _buffers.putIfAbsent(conv, () => <V2TimMessage>[]);
      // Pre-load avatar if not in cache to ensure new messages show correct avatar immediately
      // Note: FakeMessage doesn't have isSelf, so we check by comparing fromUser with selfId
      final ffi = FakeUIKit.instance.im?.ffi;
      if (ffi != null) {
        final isSelf = m.fromUser == ffi.selfId;
        if (!isSelf && _cachedFriendAvatars[m.fromUser] == null) {
          try {
            final avatarPath = await Prefs.getFriendAvatarPath(m.fromUser);
            if (avatarPath != null && avatarPath.isNotEmpty) {
              _cachedFriendAvatars[m.fromUser] = avatarPath;
            } else {
              _cachedFriendAvatars[m.fromUser] = '';
            }
          } catch (e) {
            _cachedFriendAvatars[m.fromUser] = '';
          }
        }
      }
      final mappedMsg = await _mapMsgWithFailedCheck(m);
      // Check if message already exists by msgID
      final existingIndex = list.indexWhere((msg) => msg.msgID == mappedMsg.msgID);
      if (existingIndex >= 0) {
        // Message exists - update it (important for file_done updates that change filePath and isPending)
        // CRITICAL: If file is complete (isPending=false and filePath is not in /tmp/receiving_), clear _fileProgress
        // This ensures UI doesn't show spinning state for completed files
        if (!m.isPending && m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
          final hadProgress = _fileProgress.containsKey(mappedMsg.msgID);
          if (hadProgress) {
            final oldProgress = _fileProgress[mappedMsg.msgID];
            _fileProgress.remove(mappedMsg.msgID);
            AppLogger.log('[FakeMessageProvider] ✅ File completed via file_done, removed from _fileProgress for msgID=${mappedMsg.msgID}, filePath=${m.filePath} (old progress: ${oldProgress?.received}/${oldProgress?.total})');
          } else {
            AppLogger.log('[FakeMessageProvider] File completed via file_done for msgID=${mappedMsg.msgID}, filePath=${m.filePath} (no _fileProgress entry)');
          }
        } else {
          AppLogger.log('[FakeMessageProvider] File message update: msgID=${mappedMsg.msgID}, isPending=${m.isPending}, filePath=${m.filePath}');
        }
        list[existingIndex] = mappedMsg;
        // Sort by timestamp ascending (oldest first, newest last)
        list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
        // UIKit's getMessageListForRender reverses the list, but our stream bypasses it
        // So we need to reverse the list before emitting to match UIKit's expected format
        // Reverse: newest first, oldest last (for reverse ListView, index 0 = newest at bottom)
        // Always create new message objects for the reversed list to ensure Flutter detects changes
        final reversedList = List<V2TimMessage>.from(list.map((msg) {
          // Always create a new message object to ensure Flutter detects the change
          // This is especially important for file messages where localUrl changes
          // CRITICAL: Use mappedMsg.elemType if this is the updated message, otherwise use msg.elemType
          final elemType = (msg.msgID == mappedMsg.msgID) ? mappedMsg.elemType : msg.elemType;
          final newMsg = V2TimMessage(elemType: elemType);
          // Copy all properties
          newMsg.msgID = msg.msgID;
          newMsg.userID = msg.userID;
          newMsg.timestamp = msg.timestamp;
          newMsg.isSelf = msg.isSelf;
          newMsg.sender = msg.sender;
          newMsg.groupID = msg.groupID;
          newMsg.textElem = msg.textElem;
          // CRITICAL: Recreate imageElem to ensure Flutter detects changes in imageList.localUrl
          // This is essential for images that are updated after file_done event
          if (msg.imageElem != null) {
            final oldImageElem = msg.imageElem!;
            // CRITICAL: If this is the updated message (msg.msgID == mappedMsg.msgID), use mappedMsg.imageElem directly
            // Otherwise, use msg.imageElem (which may have been updated by _mapMsg if msg == mappedMsg)
            String? effectiveLocalUrl;
            // Priority 1: Check if msg is the updated message, use mappedMsg.imageElem directly
            if (msg.msgID == mappedMsg.msgID && mappedMsg.imageElem != null) {
              final mappedImageElem = mappedMsg.imageElem!;
              // Check mappedMsg.imageElem.path
              if (mappedImageElem.path != null && (mappedImageElem.path!.contains('/avatars/') || mappedImageElem.path!.contains('/file_recv/'))) {
                final file = File(mappedImageElem.path!);
                if (file.existsSync()) {
                  effectiveLocalUrl = mappedImageElem.path;
                }
              }
              // Check mappedMsg.imageElem.imageList.localUrl
              if (effectiveLocalUrl == null && mappedImageElem.imageList != null) {
                for (final img in mappedImageElem.imageList!) {
                  if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                    effectiveLocalUrl = img.localUrl;
                    break;
                  }
                }
              }
              // Use mappedMsg.imageElem directly if it has imageList with localUrl
              if (effectiveLocalUrl != null) {
                // Create new imageList with updated localUrl
                // CRITICAL: Preserve uuid and url from mappedMsg.imageElem if available
                String? preservedUuid;
                String? preservedUrl;
                if (mappedImageElem.imageList != null) {
                  for (final img in mappedImageElem.imageList!) {
                    if (img != null && img.uuid != null) {
                      preservedUuid = img.uuid;
                      break;
                    }
                  }
                  for (final img in mappedImageElem.imageList!) {
                    if (img != null && img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                      preservedUrl = img.url;
                      break;
                    }
                  }
                }
                final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
                thumbImage.localUrl = effectiveLocalUrl;
                if (preservedUuid != null) {
                  thumbImage.uuid = preservedUuid;
                }
                if (preservedUrl != null) {
                  thumbImage.url = preservedUrl;
                } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                  // Use localUrl as url if it's not a temp path
                  thumbImage.url = effectiveLocalUrl;
                }
                final newImageList = [thumbImage];
                final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
                originImage.localUrl = effectiveLocalUrl;
                if (preservedUuid != null) {
                  originImage.uuid = preservedUuid;
                }
                if (preservedUrl != null) {
                  originImage.url = preservedUrl;
                } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                  // Use localUrl as url if it's not a temp path
                  originImage.url = effectiveLocalUrl;
                }
                newImageList.add(originImage);
                newMsg.imageElem = V2TimImageElem(
                  path: mappedImageElem.path,
                  imageList: newImageList,
                );
                AppLogger.log('[FakeMessageProvider] Updated imageElem for msgID=${msg.msgID}: path=${mappedImageElem.path}, localUrl=$effectiveLocalUrl, newMsg.imageElem.path=${newMsg.imageElem?.path}');
              } else {
                // Use mappedMsg.imageElem as-is (it should have been set correctly by _mapMsg)
                // CRITICAL: Always create new V2TimImage objects to ensure Flutter detects changes
                // CRITICAL: Must copy uuid field for downloadMessage to work
                // CRITICAL: Don't preserve /tmp/receiving_ paths as url - they will fail when used as online URLs
                newMsg.imageElem = V2TimImageElem(
                  path: mappedImageElem.path,
                  imageList: mappedImageElem.imageList?.map((img) {
                    if (img == null) return null;
                    final newImg = V2TimImage(type: img.type);
                    newImg.uuid = img.uuid; // CRITICAL: Copy uuid for downloadMessage
                    newImg.localUrl = img.localUrl;
                    // Only preserve url if it's not a temporary receiving path
                    if (img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                      newImg.url = img.url;
                    }
                    // If url was a temp path but localUrl is available and not a temp path, use localUrl as url
                    else if (img.localUrl != null && !img.localUrl!.startsWith('/tmp/receiving_')) {
                      newImg.url = img.localUrl;
                    }
                    newImg.width = img.width;
                    newImg.height = img.height;
                    newImg.size = img.size;
                    return newImg;
                  }).toList(),
                );
                final mappedImageList = mappedImageElem.imageList;
                String? mappedLocalUrl;
                if (mappedImageList != null) {
                  for (final img in mappedImageList) {
                    if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                      mappedLocalUrl = img.localUrl;
                      break;
                    }
                  }
                }
                AppLogger.log('[FakeMessageProvider] Updated imageElem for msgID=${msg.msgID}: path=${mappedImageElem.path}, imageList.localUrl=$mappedLocalUrl, newMsg.imageElem.path=${newMsg.imageElem?.path}');
              }
            } else {
              // Not the updated message, use msg.imageElem (which may have been updated by _mapMsg)
              // Check oldImageElem.path
              if (oldImageElem.path != null && (oldImageElem.path!.contains('/avatars/') || oldImageElem.path!.contains('/file_recv/'))) {
                final file = File(oldImageElem.path!);
                if (file.existsSync()) {
                  effectiveLocalUrl = oldImageElem.path;
                }
              }
              // Check oldImageElem.imageList.localUrl
              if (effectiveLocalUrl == null && oldImageElem.imageList != null) {
                for (final img in oldImageElem.imageList!) {
                  if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                    effectiveLocalUrl = img.localUrl;
                    break;
                  }
                }
              }
              // Recreate imageList with new V2TimImage objects to ensure Flutter detects changes
              List<V2TimImage?>? newImageList;
              if (effectiveLocalUrl != null) {
                // Create new imageList with updated localUrl
                // CRITICAL: Preserve uuid and url from oldImageElem.imageList if available
                String? preservedUuid;
                String? preservedUrl;
                if (oldImageElem.imageList != null) {
                  for (final img in oldImageElem.imageList!) {
                    if (img != null && img.uuid != null) {
                      preservedUuid = img.uuid;
                      break;
                    }
                  }
                  for (final img in oldImageElem.imageList!) {
                    if (img != null && img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                      preservedUrl = img.url;
                      break;
                    }
                  }
                }
                final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
                thumbImage.localUrl = effectiveLocalUrl;
                if (preservedUuid != null) {
                  thumbImage.uuid = preservedUuid;
                }
                if (preservedUrl != null) {
                  thumbImage.url = preservedUrl;
                } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                  // Use localUrl as url if it's not a temp path
                  thumbImage.url = effectiveLocalUrl;
                }
                newImageList = [thumbImage];
                final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
                originImage.localUrl = effectiveLocalUrl;
                if (preservedUuid != null) {
                  originImage.uuid = preservedUuid;
                }
                if (preservedUrl != null) {
                  originImage.url = preservedUrl;
                } else if (effectiveLocalUrl != null && !effectiveLocalUrl.startsWith('/tmp/receiving_')) {
                  // Use localUrl as url if it's not a temp path
                  originImage.url = effectiveLocalUrl;
                }
                newImageList.add(originImage);
              } else if (oldImageElem.imageList != null) {
                // No localUrl available, but preserve existing imageList structure
                // CRITICAL: Must copy uuid field for downloadMessage to work
                // CRITICAL: Don't preserve /tmp/receiving_ paths as url - they will fail when used as online URLs
                newImageList = oldImageElem.imageList!.map((img) {
                  if (img == null) return null;
                  final newImg = V2TimImage(type: img.type);
                  newImg.uuid = img.uuid; // CRITICAL: Copy uuid for downloadMessage
                  newImg.localUrl = img.localUrl;
                  // Only preserve url if it's not a temporary receiving path
                  if (img.url != null && !img.url!.startsWith('/tmp/receiving_')) {
                    newImg.url = img.url;
                  }
                  // If url was a temp path but localUrl is available and not a temp path, use localUrl as url
                  else if (img.localUrl != null && !img.localUrl!.startsWith('/tmp/receiving_')) {
                    newImg.url = img.localUrl;
                  }
                  newImg.width = img.width;
                  newImg.height = img.height;
                  newImg.size = img.size;
                  return newImg;
                }).toList();
              }
              newMsg.imageElem = V2TimImageElem(
                path: oldImageElem.path,
                imageList: newImageList,
              );
            }
          } else {
            // No imageElem in original message, but check if mappedMsg has imageElem
            // This handles the case where message type changed or imageElem was added
            if (msg.msgID == mappedMsg.msgID && mappedMsg.imageElem != null) {
              // Use mappedMsg.imageElem directly
              newMsg.imageElem = mappedMsg.imageElem;
            } else {
              newMsg.imageElem = msg.imageElem;
            }
          }
          // Handle videoElem: use mappedMsg if this is the updated message
          if (msg.msgID == mappedMsg.msgID && mappedMsg.videoElem != null) {
            newMsg.videoElem = mappedMsg.videoElem;
          } else {
            newMsg.videoElem = msg.videoElem;
          }
          // Handle soundElem: use mappedMsg if this is the updated message
          if (msg.msgID == mappedMsg.msgID && mappedMsg.soundElem != null) {
            newMsg.soundElem = mappedMsg.soundElem;
          } else {
            newMsg.soundElem = msg.soundElem;
          }
          // CRITICAL: Recreate fileElem to ensure Flutter detects changes in localUrl
          // This is essential for file messages that are updated after file reception
          if (msg.fileElem != null) {
            final oldFileElem = msg.fileElem!;
            // CRITICAL: If this is the updated message (msg.msgID == mappedMsg.msgID), use mappedMsg.fileElem directly
            // Otherwise, ensure we preserve localUrl if file is already received
            if (msg.msgID == mappedMsg.msgID && mappedMsg.fileElem != null) {
              // Use mappedMsg.fileElem directly (it should have been set correctly by _mapMsg)
              newMsg.fileElem = mappedMsg.fileElem;
            } else {
              // Not the updated message, but ensure we preserve localUrl if file is already received
              // Check if fileElem.path is in file_recv directory (file already received)
              String? preservedLocalUrl = oldFileElem.localUrl;
              if (preservedLocalUrl == null || preservedLocalUrl.isEmpty) {
                // Try to recover localUrl from path if it's in file_recv directory
                if (oldFileElem.path != null && (oldFileElem.path!.contains('/file_recv/') || oldFileElem.path!.contains('/avatars/'))) {
                  final file = File(oldFileElem.path!);
                  if (file.existsSync()) {
                    preservedLocalUrl = oldFileElem.path;
                  }
                }
              }
              // Recreate fileElem with preserved localUrl
              // CRITICAL: Don't preserve /tmp/receiving_ paths as url - they will fail when used as online URLs
              String? preservedUrl = oldFileElem.url;
              if (preservedUrl != null && preservedUrl.startsWith('/tmp/receiving_')) {
                // If url is a temp path, use localUrl as url if available and not a temp path
                if (preservedLocalUrl != null && !preservedLocalUrl.startsWith('/tmp/receiving_')) {
                  preservedUrl = preservedLocalUrl;
                } else {
                  preservedUrl = null; // Don't set url if it's a temp path
                }
              }
              newMsg.fileElem = V2TimFileElem(
                path: oldFileElem.path,
                fileName: oldFileElem.fileName,
                UUID: oldFileElem.UUID,
                url: preservedUrl,
                fileSize: oldFileElem.fileSize,
                localUrl: preservedLocalUrl ?? oldFileElem.localUrl, // Preserve localUrl if available
              );
            }
          } else {
            newMsg.fileElem = msg.fileElem;
          }
          newMsg.customElem = msg.customElem;
          newMsg.status = msg.status;
          newMsg.nameCard = msg.nameCard;
          newMsg.friendRemark = msg.friendRemark;
          newMsg.nickName = msg.nickName;
          newMsg.seq = msg.seq;
          newMsg.id = msg.id;
          return newMsg;
        }).toList().reversed);
        // DEBUG: Log the updated message's imageElem.path before emitting
        AppLogger.log('[FakeMessageProvider] About to emit reversedList to stream: conv=$conv, reversedList.length=${reversedList.length}, mappedMsg.msgID=${mappedMsg.msgID}');
        bool foundUpdatedMsg = false;
        for (final msg in reversedList) {
          if (msg.msgID == mappedMsg.msgID) {
            foundUpdatedMsg = true;
            AppLogger.log('[FakeMessageProvider] Found updated message in reversedList: msgID=${msg.msgID}, imageElem=${msg.imageElem != null ? "not null" : "null"}');
            if (msg.imageElem != null) {
              final imageList = msg.imageElem!.imageList;
              String? localUrl;
              if (imageList != null) {
                for (final img in imageList) {
                  if (img != null && img.localUrl != null && img.localUrl!.isNotEmpty) {
                    localUrl = img.localUrl;
                    break;
                  }
                }
              }
              AppLogger.log('[FakeMessageProvider] Emitting updated message to stream: msgID=${msg.msgID}, imageElem.path=${msg.imageElem!.path}, imageList.length=${imageList?.length ?? 0}, imageList.localUrl=$localUrl');
            } else {
              // Only warn if this is supposed to be an image message (elemType is IMAGE)
              // For file messages, imageElem being null is expected
              if (msg.elemType == MessageElemType.V2TIM_ELEM_TYPE_IMAGE) {
                AppLogger.log('[FakeMessageProvider] WARNING: Updated image message found but imageElem is null!');
              }
            }
            break;
          }
        }
        if (!foundUpdatedMsg) {
          AppLogger.log('[FakeMessageProvider] WARNING: Updated message (msgID=${mappedMsg.msgID}) NOT found in reversedList! reversedList contains: ${reversedList.map((m) => m.msgID).join(", ")}');
        }
        AppLogger.log('[FakeMessageProvider] Calling _ctrls[$conv]?.add(reversedList) - controller exists: ${_ctrls[conv] != null}');
        _ctrls[conv]?.add(reversedList);
        AppLogger.log('[FakeMessageProvider] Successfully added reversedList to stream for conv=$conv');
        
        // CRITICAL: Send messageNeedUpdate event to UIKit to trigger widget refresh
        // This is essential for images that are updated after file_done event
        // UIKit's TencentCloudChatMessageImage widget listens for messageNeedUpdate events
        // to detect changes in imageElem.path and imageList.localUrl
        try {
          // Find the updated message in reversedList
          final updatedMsg = reversedList.firstWhere(
            (msg) => msg.msgID == mappedMsg.msgID,
            orElse: () => mappedMsg,
          );
          
          // Only send messageNeedUpdate if the message has imageElem or fileElem with updated path
          if (updatedMsg.imageElem != null) {
            final imagePath = updatedMsg.imageElem!.path;
            final hasLocalUrl = updatedMsg.imageElem!.imageList?.any((img) => 
              img != null && img.localUrl != null && img.localUrl!.isNotEmpty
            ) ?? false;
            
            // Send messageNeedUpdate if path is in avatars or file_recv directory (file received)
            if (imagePath != null && (imagePath.contains('/avatars/') || imagePath.contains('/file_recv/')) && hasLocalUrl) {
              AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for msgID=${updatedMsg.msgID}, path=$imagePath');
              TencentCloudChat.instance.dataInstance.messageData.messageNeedUpdate = updatedMsg;
              // Extract userID/groupID from conversationID
              String? userID;
              String? groupID;
              if (conv.startsWith('c2c_')) {
                userID = conv.substring(4);
              } else if (conv.startsWith('group_')) {
                groupID = conv.substring(6);
              }
              TencentCloudChat.instance.dataInstance.messageData.notifyListener(
                TencentCloudChatMessageDataKeys.messageNeedUpdate as dynamic,
                userID: userID,
                groupID: groupID,
              );
            }
          } else if (updatedMsg.fileElem != null) {
            // Also send messageNeedUpdate for file messages when file is received
            final filePath = updatedMsg.fileElem!.path;
            final hasLocalUrl = updatedMsg.fileElem!.localUrl != null && updatedMsg.fileElem!.localUrl!.isNotEmpty;

            // Check if message isPending status changed (from true to false) - this indicates file completion
            final customData = updatedMsg.customElem?.data;
            final isPending = customData != null && customData.contains('"isPending":true');
            final isNotPending = !isPending;

            // Send messageNeedUpdate if:
            // 1. File path is in file_recv/avatars directory and has localUrl (file received)
            // 2. OR file has localUrl and isPending is false (file completed, may be in Downloads directory)
            // This ensures UI updates even when file is moved to Downloads directory
            final shouldUpdate = (filePath != null && (filePath.contains('/file_recv/') || filePath.contains('/avatars/')) && hasLocalUrl) ||
                                 (hasLocalUrl && isNotPending);

            if (shouldUpdate) {
              AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for file msgID=${updatedMsg.msgID}, path=$filePath, localUrl=${updatedMsg.fileElem!.localUrl}, isPending=$isPending');
              TencentCloudChat.instance.dataInstance.messageData.messageNeedUpdate = updatedMsg;
              // Extract userID/groupID from conversationID
              String? userID;
              String? groupID;
              if (conv.startsWith('c2c_')) {
                userID = conv.substring(4);
              } else if (conv.startsWith('group_')) {
                groupID = conv.substring(6);
              }
              TencentCloudChat.instance.dataInstance.messageData.notifyListener(
                TencentCloudChatMessageDataKeys.messageNeedUpdate as dynamic,
                userID: userID,
                groupID: groupID,
              );
            }
          } else if (updatedMsg.videoElem != null) {
            // Send messageNeedUpdate for video messages when file is received
            final videoPath = updatedMsg.videoElem!.videoPath;
            final hasLocalVideoUrl = updatedMsg.videoElem!.localVideoUrl != null && updatedMsg.videoElem!.localVideoUrl!.isNotEmpty;
            final customData = updatedMsg.customElem?.data;
            final isPending = customData != null && customData.contains('"isPending":true');
            final shouldUpdate = (videoPath != null && (videoPath.contains('/file_recv/') || videoPath.contains('/avatars/')) && hasLocalVideoUrl) ||
                                 (hasLocalVideoUrl && !isPending);
            if (shouldUpdate) {
              AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for video msgID=${updatedMsg.msgID}, path=$videoPath, localVideoUrl=${updatedMsg.videoElem!.localVideoUrl}');
              TencentCloudChat.instance.dataInstance.messageData.messageNeedUpdate = updatedMsg;
              String? userID;
              String? groupID;
              if (conv.startsWith('c2c_')) {
                userID = conv.substring(4);
              } else if (conv.startsWith('group_')) {
                groupID = conv.substring(6);
              }
              TencentCloudChat.instance.dataInstance.messageData.notifyListener(
                TencentCloudChatMessageDataKeys.messageNeedUpdate as dynamic,
                userID: userID,
                groupID: groupID,
              );
            }
          } else if (updatedMsg.soundElem != null) {
            // Send messageNeedUpdate for audio messages when file is received
            final soundPath = updatedMsg.soundElem!.path;
            final hasLocalUrl = updatedMsg.soundElem!.localUrl != null && updatedMsg.soundElem!.localUrl!.isNotEmpty;
            final customData = updatedMsg.customElem?.data;
            final isPending = customData != null && customData.contains('"isPending":true');
            final shouldUpdate = (soundPath != null && (soundPath.contains('/file_recv/') || soundPath.contains('/avatars/')) && hasLocalUrl) ||
                                 (hasLocalUrl && !isPending);
            if (shouldUpdate) {
              AppLogger.log('[FakeMessageProvider] Sending messageNeedUpdate event for audio msgID=${updatedMsg.msgID}, path=$soundPath, localUrl=${updatedMsg.soundElem!.localUrl}');
              TencentCloudChat.instance.dataInstance.messageData.messageNeedUpdate = updatedMsg;
              String? userID;
              String? groupID;
              if (conv.startsWith('c2c_')) {
                userID = conv.substring(4);
              } else if (conv.startsWith('group_')) {
                groupID = conv.substring(6);
              }
              TencentCloudChat.instance.dataInstance.messageData.notifyListener(
                TencentCloudChatMessageDataKeys.messageNeedUpdate as dynamic,
                userID: userID,
                groupID: groupID,
              );
            }
          }
        } catch (e) {
          // Ignore errors during messageNeedUpdate event emission
          AppLogger.log('[FakeMessageProvider] Error sending messageNeedUpdate: $e');
        }
      } else {
        // Message doesn't exist by msgID - check if there's a temporary message (created_temp_id-*)
        // that matches by content and timestamp (for resend scenarios)
        // This prevents duplicate messages when resending: the temporary message will be replaced
        // by the real message from FakeMessage event
        int? tempMsgIndex;
        final mappedText = mappedMsg.textElem?.text ?? '';
        final mappedTimestamp = mappedMsg.timestamp ?? 0;
        for (int i = 0; i < list.length; i++) {
          final msg = list[i];
          final msgMsgID = msg.msgID;
          final msgStatus = msg.status;
          // Check if this is a temporary message (created_temp_id-*) with status SENDING
          if (msgMsgID != null && 
              msgMsgID.startsWith('created_temp_id-') && 
              msgStatus == MessageStatus.V2TIM_MSG_STATUS_SENDING) {
            // Check if content and timestamp match (within 5 seconds tolerance for resend)
            final msgText = msg.textElem?.text ?? '';
            final msgTimestamp = msg.timestamp ?? 0;
            if (msgText == mappedText && 
                (mappedTimestamp - msgTimestamp).abs() < 5000) {
              tempMsgIndex = i;
              break;
            }
          }
        }
        
        if (tempMsgIndex != null) {
          // Found a temporary message that matches - replace it with the real message
          // This handles the resend scenario where a temporary message was inserted
          // and then FakeMessage event arrives with the real msgID
          list[tempMsgIndex] = mappedMsg;
          // Sort by timestamp ascending (oldest first, newest last)
          list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
          // Emit updated list
          final reversedList = List<V2TimMessage>.from(list.reversed);
          _ctrls[conv]?.add(reversedList);
        } else {
          // New message - add it
          list.add(mappedMsg);
          // Sort by timestamp ascending (oldest first, newest last)
          list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
          // UIKit's getMessageListForRender reverses the list, but our stream bypasses it
          // So we need to reverse the list before emitting to match UIKit's expected format
          // Reverse: newest first, oldest last (for reverse ListView, index 0 = newest at bottom)
          final reversedList = List<V2TimMessage>.from(list.reversed);
          AppLogger.log('[FakeMessageProvider] New msg added: msgID=${mappedMsg.msgID}, conv=$conv, elemType=${mappedMsg.elemType}, bufferSize=${list.length}, ctrlExists=${_ctrls[conv] != null}');
          _ctrls[conv]?.add(reversedList);
        }
      }
    });
  }

  /// Map FakeMessage to V2TimMessage, checking failed persistence to preserve failed status
  Future<V2TimMessage> _mapMsgWithFailedCheck(FakeMessage m) async {
    final msg = _mapMsg(m);
    
    // CRITICAL: Check if message is in failed persistence list before setting status
    // This ensures that failed messages (emitted from updateMessageInBuffer) maintain their failed status
    // even if isPending=false, isReceived=false, isRead=false
    try {
      // Extract userID/groupID from conversationID
      String? userID;
      String? groupID;
      if (m.conversationID.startsWith('c2c_')) {
        userID = m.conversationID.substring(4);
      } else if (m.conversationID.startsWith('group_')) {
        groupID = m.conversationID.substring(6);
      }
      
      final currentToxId = await Prefs.getCurrentAccountToxId();
      final failedMessagesData = await Tim2ToxFailedMessagePersistence.loadFailedMessages(
        userID: userID,
        groupID: groupID,
        accountToxId: currentToxId,
      );
      
      // Check if this message is in the failed list
      for (final failedMsgData in failedMessagesData) {
        final failedMsgID = failedMsgData['msgID'] as String?;
        final failedID = failedMsgData['id'] as String?;
        
        if ((failedMsgID != null && failedMsgID == m.msgID) ||
            (failedID != null && failedID == m.msgID)) {
          // Message is in failed list - preserve failed status
          msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
          break;
        }
      }
    } catch (e) {
      // If check fails, continue with normal mapping
    }
    
    return msg;
  }

  /// Find the conversation ID that matches a given userID, handling Tox ID
  /// format differences (64 vs 76 chars). Returns null if not found.
  String? findConversationForUser(String userID) {
    final normalized = normalizeToxId(userID);
    for (final key in _ctrls.keys) {
      if (key.startsWith('c2c_') &&
          normalizeToxId(key.substring(4)) == normalized) {
        return key;
      }
    }
    for (final key in _buffers.keys) {
      if (key.startsWith('c2c_') &&
          normalizeToxId(key.substring(4)) == normalized) {
        return key;
      }
    }
    return null;
  }

  /// Map a call record FakeMessage to V2TimMessage with custom element.
  V2TimMessage _mapCallRecordMsg(FakeMessage m) {
    AppLogger.log('[FakeMessageProvider] _mapCallRecordMsg: msgID=${m.msgID}, conv=${m.conversationID}, textLen=${m.text.length}');
    final msg = V2TimMessage(elemType: MessageElemType.V2TIM_ELEM_TYPE_CUSTOM);
    msg.msgID = m.msgID;
    msg.timestamp = (m.timestampMs ~/ 1000);

    // Set userID/groupID from conversationID
    if (m.conversationID.startsWith('c2c_')) {
      msg.userID = m.conversationID.substring(4);
    } else if (m.conversationID.startsWith('group_')) {
      msg.groupID = m.conversationID.substring(6);
    }

    // Call record data stored in text field as JSON
    msg.customElem = V2TimCustomElem(data: m.text, desc: '', extension: '');
    // Readable summary for session list / getMessageSummary (like [image] for image messages)
    final callLabel = TencentCloudChatIntl().localization?.call ?? 'Call';
    msg.textElem = V2TimTextElem(text: '[$callLabel]');

    // Set sender info
    final selfId = TencentCloudChat.instance.dataInstance.basic.currentUser?.userID;
    msg.isSelf = (selfId != null && compareToxIds(m.fromUser, selfId));
    msg.sender = m.fromUser;
    msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_SUCC;
    AppLogger.log('[FakeMessageProvider] _mapCallRecordMsg: elemType=${msg.elemType}, isSelf=${msg.isSelf}, customElem.data=${msg.customElem?.data?.substring(0, 80)}...');

    // Set faceUrl for avatar display
    if (msg.isSelf ?? false) {
      if (_cachedSelfAvatarPath != null && _cachedSelfAvatarPath!.isNotEmpty) {
        msg.faceUrl = _cachedSelfAvatarPath;
      }
    } else {
      final friendAvatarPath = _cachedFriendAvatars[m.fromUser];
      if (friendAvatarPath != null && friendAvatarPath.isNotEmpty) {
        msg.faceUrl = friendAvatarPath;
      }
    }

    return msg;
  }

  V2TimMessage _mapMsg(FakeMessage m) {
    // Special handling for call record messages
    if (m.mediaKind == 'call_record') {
      return _mapCallRecordMsg(m);
    }

    // Determine element type based on mediaKind and filePath
    int elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
    if (m.filePath != null && m.mediaKind != null) {
      switch (m.mediaKind) {
        case 'image':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_IMAGE;
          break;
        case 'video':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_VIDEO;
          break;
        case 'audio':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_SOUND;
          break;
        case 'file':
          elemType = MessageElemType.V2TIM_ELEM_TYPE_FILE;
          break;
        default:
          elemType = MessageElemType.V2TIM_ELEM_TYPE_TEXT;
      }
    }
    
    final msg = V2TimMessage(elemType: elemType);
    msg.msgID = m.msgID;
    msg.timestamp = (m.timestampMs ~/ 1000);
    
    // CRITICAL: For C2C messages, userID should be the receiver (the other person), not the sender
    // For self-sent messages: userID = receiver (the other person), fromUser = selfId
    // For received messages: userID = sender (the other person), fromUser = sender
    // Extract receiver ID from conversationID (c2c_<receiverID>)
    if (m.conversationID.startsWith('c2c_')) {
      final receiverID = m.conversationID.substring(4);
      msg.userID = receiverID;
    } else if (m.conversationID.startsWith('group_')) {
      final groupID = m.conversationID.substring(6);
      msg.groupID = groupID;
    } else {
      // Fallback: use fromUser (for backward compatibility)
      msg.userID = m.fromUser;
    }
    
    // Set appropriate element based on media type
    if (m.filePath != null && m.mediaKind != null) {
      final file = File(m.filePath!);
      // Use original fileName if available (to avoid showing id-prefixed names), otherwise extract from path
      final fileName = m.fileName ?? m.filePath!.split('/').last;
      
      switch (m.mediaKind) {
        case 'image':
          // Set image element with local path for UIKit to display
          // Check if this is a receiving file (temporary path indicates receiving)
          final isReceiving = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final fileExists = m.filePath != null ? file.existsSync() : false;
          // Check if we have progress information for this message
          final progress = _fileProgress[m.msgID];
          // Determine localUrl: if file is complete (not receiving and file exists), set localUrl
          // UIKit uses localUrl in imageList to determine if image is downloaded
          String? localUrl;
          // Priority 1: If isPending is false, file is complete - set localUrl regardless of file existence check
          if (!m.isPending && m.filePath != null && !isReceiving) {
            localUrl = m.filePath;
          } else if (progress != null && progress.received >= progress.total && progress.total > 0) {
            // Progress indicates file is complete
            if (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
              localUrl = progress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              localUrl = m.filePath;
            }
          } else if (progress != null && progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
            // Progress has a valid path (from file_done or progress_recv), use it even if file is still receiving
            final progressFile = File(progress.path!);
            if (progressFile.existsSync()) {
              localUrl = progress.path;
            }
          } else if (!isReceiving && m.filePath != null && fileExists) {
            // File is complete and exists, set localUrl so UIKit knows it's downloaded
            localUrl = m.filePath;
          } else if (isReceiving && m.filePath != null && fileExists) {
            // File is receiving but already exists (fast transfer), set localUrl so UIKit can display it
            localUrl = m.filePath;
          }
          // CRITICAL: For images, also check if filePath is in file_recv or avatars directory (file already received)
          // This handles the case where file_done event updated the message but _mapMsg is called before progress update
          if (localUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final file = File(m.filePath!);
            if (file.existsSync()) {
              localUrl = m.filePath;
            }
          }
          // Create imageList with localUrl for UIKit to check hasLocalImage
          // CRITICAL: Also set uuid and url for downloadMessage to work
          final imageList = <V2TimImage?>[];
          // Generate UUID from msgID for download identification
          final imageUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          final imagePath = m.filePath ?? localUrl;
          // CRITICAL: Don't use /tmp/receiving_ paths as URL - they are temporary and will fail when used as online URLs
          // Only use valid local paths (file_recv, avatars) or null if still receiving
          String? imageUrl;
          if (imagePath != null && !imagePath.startsWith('/tmp/receiving_')) {
            // Use local path as URL for Tox protocol (only if not a temp receiving path)
            imageUrl = imagePath;
          } else if (localUrl != null && !localUrl.startsWith('/tmp/receiving_')) {
            // Use localUrl if available and not a temp path
            imageUrl = localUrl;
          }
          // If imageUrl is still null, don't set it (let UIKit handle download)
          
          if (localUrl != null || (imagePath != null && !imagePath.startsWith('/tmp/receiving_'))) {
            // Create thumb image with localUrl (UIKit checks thumb image by default)
            final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
            thumbImage.uuid = imageUuid;
            if (imageUrl != null) {
              thumbImage.url = imageUrl;
            }
            thumbImage.localUrl = localUrl;
            if (fileExists && m.filePath != null) {
              thumbImage.size = file.lengthSync();
            }
            imageList.add(thumbImage);
            // Also create origin image with localUrl
            final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
            originImage.uuid = imageUuid;
            if (imageUrl != null) {
              originImage.url = imageUrl;
            }
            originImage.localUrl = localUrl;
            if (fileExists && m.filePath != null) {
              originImage.size = file.lengthSync();
            }
            imageList.add(originImage);
          } else {
            // Even if localUrl is null, create imageList with uuid for downloadMessage
            // Don't set url if it's a temp receiving path - UIKit will handle download
            final thumbImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_THUMB);
            thumbImage.uuid = imageUuid;
            // Only set url if it's not a temp receiving path
            if (imageUrl != null) {
              thumbImage.url = imageUrl;
            }
            imageList.add(thumbImage);
            final originImage = V2TimImage(type: V2TIM_IMAGE_TYPE.V2TIM_IMAGE_TYPE_ORIGIN);
            originImage.uuid = imageUuid;
            // Only set url if it's not a temp receiving path
            if (imageUrl != null) {
              originImage.url = imageUrl;
            }
            imageList.add(originImage);
          }
          // CRITICAL: Always create imageElem with imageList, even if imageList is empty
          // This ensures imageElem is not null, which is required for UIKit to render the image
          // CRITICAL: Use localUrl or final path (not temp path) for imageElem.path if available
          // This ensures isAlreadyComplete check can correctly detect completed files
          final imageElemPath = (localUrl != null && !localUrl.startsWith('/tmp/receiving_')) 
              ? localUrl 
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) 
                  ? m.filePath 
                  : m.filePath);
          msg.imageElem = V2TimImageElem(
            path: imageElemPath,
            imageList: imageList.isNotEmpty ? imageList : (imageList.isEmpty ? [] : null),
          );
          // Debug: Log image message creation
          // Also set text element with file name as fallback
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            // Use original fileName if available, otherwise use extracted fileName
            msg.textElem = V2TimTextElem(text: m.fileName ?? fileName);
          }
          break;
        case 'file':
          // Set file element with local path and file name
          // Check if this is a receiving file (temporary path indicates receiving)
          final isReceiving = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final fileExists = m.filePath != null ? file.existsSync() : false;
          final fileSize = fileExists ? file.lengthSync() : null;
          // Check if we have progress information for this message
          final progress = _fileProgress[m.msgID];
          // Determine localUrl: if file is complete (not receiving and file exists), set localUrl
          // UIKit uses localUrl to determine if file is downloaded
          String? localUrl;
          // Priority 1: If isPending is false, file is complete - set localUrl regardless of file existence check
          // This handles the case where file_done has updated the message but file.existsSync() might fail due to timing
          if (!m.isPending && m.filePath != null && !isReceiving) {
            localUrl = m.filePath;
          } else if (progress != null && progress.received >= progress.total && progress.total > 0) {
            // Progress indicates file is complete - check this BEFORE isReceiving check
            // Use progress.path if available (from progress_recv events), otherwise use m.filePath if it's not a temp path
            if (progress.path != null && !progress.path!.startsWith('/tmp/receiving_')) {
              localUrl = progress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              localUrl = m.filePath;
            }
          } else if (isReceiving) {
            // File is still receiving, don't set localUrl yet (UIKit will show progress)
            localUrl = null;
          } else if (m.filePath != null && fileExists) {
            // File is complete and exists, set localUrl so UIKit knows it's downloaded
            localUrl = m.filePath;
          }
          // CRITICAL: For files, also check if filePath is in file_recv or avatars directory (file already received)
          // This handles the case where file_done event updated the message but _mapMsg is called before progress update
          // Similar to image messages, this ensures localUrl is set when file is in file_recv directory
          if (localUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final file = File(m.filePath!);
            if (file.existsSync()) {
              localUrl = m.filePath;
            }
          }
          // Generate UUID from msgID for download identification
          final fileUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          // CRITICAL: Don't use /tmp/receiving_ paths as URL - they are temporary and will fail when used as online URLs
          // Only use valid local paths (file_recv) or null if still receiving
          String? fileUrl;
          if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
            // Use local path as URL for Tox protocol (only if not a temp receiving path)
            fileUrl = m.filePath;
          } else if (localUrl != null && !localUrl.startsWith('/tmp/receiving_')) {
            // Use localUrl if available and not a temp path
            fileUrl = localUrl;
          }
          // If fileUrl is still null, don't set it (let UIKit handle download)
          
          // CRITICAL: Use localUrl or final path (not temp path) for fileElem.path if available
          // This ensures isAlreadyComplete check can correctly detect completed files
          final fileElemPath = (localUrl != null && !localUrl.startsWith('/tmp/receiving_')) 
              ? localUrl 
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) 
                  ? m.filePath 
                  : m.filePath);
          msg.fileElem = V2TimFileElem(
            path: fileElemPath,
            fileName: fileName,
            UUID: fileUuid, // Required for downloadMessage
            url: fileUrl, // Required for downloadMessage (null if still receiving)
            fileSize: fileSize ?? (progress != null ? progress.total : null),
            localUrl: localUrl,
          );
          // Also set text element with file name
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        case 'video':
          // Set video element with proper V2TimVideoElem (UIKit expects videoElem for video messages)
          final isReceivingVideo = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final videoFileExists = m.filePath != null ? file.existsSync() : false;
          final videoFileSize = videoFileExists ? file.lengthSync() : null;
          final videoProgress = _fileProgress[m.msgID];
          // Determine localVideoUrl using same logic as file/image
          String? localVideoUrl;
          if (!m.isPending && m.filePath != null && !isReceivingVideo) {
            localVideoUrl = m.filePath;
          } else if (videoProgress != null && videoProgress.received >= videoProgress.total && videoProgress.total > 0) {
            if (videoProgress.path != null && !videoProgress.path!.startsWith('/tmp/receiving_')) {
              localVideoUrl = videoProgress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              localVideoUrl = m.filePath;
            }
          } else if (!isReceivingVideo && m.filePath != null && videoFileExists) {
            localVideoUrl = m.filePath;
          }
          // Check file_recv/avatars directory
          if (localVideoUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final f = File(m.filePath!);
            if (f.existsSync()) {
              localVideoUrl = m.filePath;
            }
          }
          final videoUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          String? videoUrl;
          if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
            videoUrl = m.filePath;
          } else if (localVideoUrl != null && !localVideoUrl.startsWith('/tmp/receiving_')) {
            videoUrl = localVideoUrl;
          }
          final videoElemPath = (localVideoUrl != null && !localVideoUrl.startsWith('/tmp/receiving_'))
              ? localVideoUrl
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_'))
                  ? m.filePath
                  : m.filePath);
          msg.videoElem = V2TimVideoElem(
            videoPath: videoElemPath,
            UUID: videoUuid,
            videoSize: videoFileSize ?? (videoProgress != null ? videoProgress.total : null),
            duration: 0, // Duration unknown from Tox protocol
            videoUrl: videoUrl,
            localVideoUrl: localVideoUrl,
          );
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        case 'audio':
          // Set sound element with proper V2TimSoundElem (UIKit expects soundElem for audio messages)
          final isReceivingAudio = m.filePath != null && m.filePath!.startsWith('/tmp/receiving_');
          final audioFileExists = m.filePath != null ? file.existsSync() : false;
          final audioFileSize = audioFileExists ? file.lengthSync() : null;
          final audioProgress = _fileProgress[m.msgID];
          // Determine localUrl using same logic as file/image
          String? audioLocalUrl;
          if (!m.isPending && m.filePath != null && !isReceivingAudio) {
            audioLocalUrl = m.filePath;
          } else if (audioProgress != null && audioProgress.received >= audioProgress.total && audioProgress.total > 0) {
            if (audioProgress.path != null && !audioProgress.path!.startsWith('/tmp/receiving_')) {
              audioLocalUrl = audioProgress.path;
            } else if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
              audioLocalUrl = m.filePath;
            }
          } else if (!isReceivingAudio && m.filePath != null && audioFileExists) {
            audioLocalUrl = m.filePath;
          }
          // Check file_recv/avatars directory
          if (audioLocalUrl == null && m.filePath != null && (m.filePath!.contains('/file_recv/') || m.filePath!.contains('/avatars/'))) {
            final f = File(m.filePath!);
            if (f.existsSync()) {
              audioLocalUrl = m.filePath;
            }
          }
          final audioUuid = m.msgID.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
          String? audioUrl;
          if (m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_')) {
            audioUrl = m.filePath;
          } else if (audioLocalUrl != null && !audioLocalUrl.startsWith('/tmp/receiving_')) {
            audioUrl = audioLocalUrl;
          }
          final soundElemPath = (audioLocalUrl != null && !audioLocalUrl.startsWith('/tmp/receiving_'))
              ? audioLocalUrl
              : ((m.filePath != null && !m.filePath!.startsWith('/tmp/receiving_'))
                  ? m.filePath
                  : m.filePath);
          msg.soundElem = V2TimSoundElem(
            path: soundElemPath,
            UUID: audioUuid,
            dataSize: audioFileSize ?? (audioProgress != null ? audioProgress.total : null),
            duration: 0, // Duration unknown from Tox protocol
            url: audioUrl,
            localUrl: audioLocalUrl,
          );
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else {
            msg.textElem = V2TimTextElem(text: fileName);
          }
          break;
        default:
          // For unknown types, use text element
          if (m.text.isNotEmpty) {
            msg.textElem = V2TimTextElem(text: m.text);
          } else if (m.filePath != null) {
            msg.textElem = V2TimTextElem(text: fileName);
          }
      }
    } else {
      // No file path - just set text element
      // CRITICAL: For text messages, always set textElem even if text is empty
      // This ensures text messages have content (even if empty string)
      // For failed messages restored from persistence, text might be empty but we still need textElem
      // Since FakeMessage doesn't have elemType, we determine if it's a text message by checking if there's no filePath
      // If there's no filePath and no mediaKind, it's likely a text message
      if (m.filePath == null && m.mediaKind == null) {
        // This is likely a text message - always set textElem
        msg.textElem = V2TimTextElem(text: m.text.isNotEmpty ? m.text : '');
      } else if (m.text.isNotEmpty) {
        // For other message types, only set textElem if text is not empty
        msg.textElem = V2TimTextElem(text: m.text);
      }
    }
    
    final selfId = TencentCloudChat.instance.dataInstance.basic.currentUser?.userID;
    // Normalize IDs for comparison (Tox IDs can be 64 or 76 characters)
    msg.isSelf = (selfId != null && compareToxIds(m.fromUser, selfId));
    
    // Set custom data for pending status (if message is pending)
    // Note: V2TimCustomElem.data expects String, not Uint8List
    if (m.isPending) {
      msg.customElem = V2TimCustomElem(data: '{"isPending":true}');
    }
    
    // Set message status and read receipt status
    // UIKit uses status field: 1=SENDING, 2=SEND_SUCC, 3=SEND_FAIL
    // For self-sent messages, set status based on receipt
    if (msg.isSelf ?? false) {
      if (m.isPending) {
        // Check if this is an old message (likely from before client restart)
        // If message is older than 10 seconds, it's likely a pending message from before restart
        // and should be marked as failed. This handles the case where client restarted
        // and old pending messages are loaded from history.
        final messageAge = DateTime.now().millisecondsSinceEpoch - m.timestampMs;
        if (messageAge > 10000) {
          // Old pending message (likely from before restart) - mark as failed
          msg.status = 3; // V2TIM_MSG_STATUS_SEND_FAIL
        } else {
          // New pending message (just sent, less than 10 seconds old) - mark as sending
          // Note: If message fails to send (e.g., friend is offline), sendMessageFinalPhase
          // will update the status to SEND_FAIL via messageNeedUpdate
          msg.status = 1; // V2TIM_MSG_STATUS_SENDING
        }
      } else if (m.isRead) {
        msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC
        msg.isPeerRead = true; // Message has been read
      } else if (m.isReceived) {
        msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC
        msg.isPeerRead = false; // Message received but not read yet
      } else {
        msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC (default for sent messages)
        msg.isPeerRead = false;
      }
    } else {
      // For received messages, status is always SEND_SUCC
      msg.status = 2; // V2TIM_MSG_STATUS_SEND_SUCC
    }
    
    // Set faceUrl for avatar display
    // For self messages, use cached avatar path
    // For others' messages, get from friend avatar path storage
    // Note: UIKit now supports local file paths, so we can set faceUrl for all valid paths
    if (msg.isSelf ?? false) {
      if (_cachedSelfAvatarPath != null && _cachedSelfAvatarPath!.isNotEmpty) {
        msg.faceUrl = _cachedSelfAvatarPath;
      }
    } else {
      String? friendAvatarPath = _cachedFriendAvatars[m.fromUser];
      if (friendAvatarPath == null) {
        Prefs.getFriendAvatarPath(m.fromUser).then((avatarPath) {
          if (avatarPath != null && avatarPath.isNotEmpty) {
            _cachedFriendAvatars[m.fromUser] = avatarPath;
          } else {
            _cachedFriendAvatars[m.fromUser] = '';
          }
        });
      } else if (friendAvatarPath.isNotEmpty) {
        msg.faceUrl = friendAvatarPath;
      }
    }

    return msg;
  }

  @override
  Stream<List<V2TimMessage>> streamFor({String? userID, String? groupID}) {
    final conv = (groupID != null && groupID.isNotEmpty) ? 'group_$groupID' : 'c2c_$userID';
    final ctrl = _ctrls.putIfAbsent(conv, () => StreamController.broadcast());
    
    // Check if buffer already has messages
    final hasBuffer = _buffers.containsKey(conv) && _buffers[conv]!.isNotEmpty;
    
    // CRITICAL: Always reload history when stream is requested, even if buffer has messages
    // This ensures that when switching pages and returning, failed messages are restored
    // Previously, we only loaded history if buffer was empty, but this caused failed messages
    // to show as success after page switch because history wasn't reloaded
    // Use Future.microtask to ensure this happens after the stream is set up
    Future.microtask(() {
      _loadHistoryForConversation(conv);
    });
    
    // If buffer already has messages, emit them immediately (for real-time updates)
    // But we still reload history in the background to ensure failed messages are restored
    if (hasBuffer) {
      // UIKit's getMessageListForRender reverses the list, so we need to reverse here too
      final reversedList = List<V2TimMessage>.from(_buffers[conv]!.reversed);
      ctrl.add(reversedList);
    }
    
    return ctrl.stream;
  }

  Future<void> _loadHistoryForConversation(String conversationID) async {
    final mgr = FakeUIKit.instance.messageManager;
    if (mgr == null) {
      return;
    }
    
    try {
      final hist = await mgr.getHistory(conversationID);

      // Pre-load avatars for all message senders so _mapMsg can set faceUrl synchronously.
      // Without this, the async cache is empty when history messages are first mapped,
      // causing all message bubbles to fall back to the default avatar.
      final ffiInstance = FakeUIKit.instance.im?.ffi;
      final selfId = ffiInstance?.selfId;
      if (_cachedSelfAvatarPath == null) {
        _cachedSelfAvatarPath = await Prefs.getAvatarPath();
      }
      final senderIds = hist.map((h) => h.fromUser).whereType<String>().toSet();
      for (final senderId in senderIds) {
        if (senderId == selfId) continue;
        if (!_cachedFriendAvatars.containsKey(senderId)) {
          final avatarPath = await Prefs.getFriendAvatarPath(senderId);
          _cachedFriendAvatars[senderId] = avatarPath ?? '';
        }
      }

      // Ensure buffer exists (it should be created by streamFor, but create it here if missing)
      if (!_buffers.containsKey(conversationID)) {
        _buffers[conversationID] = <V2TimMessage>[];
      }
      
      final list = _buffers[conversationID]!;
      
      // Extract userID and groupID from conversationID for restoring failed messages
      String? userID;
      String? groupID;
      if (conversationID.startsWith('c2c_')) {
        userID = conversationID.substring(4);
      } else if (conversationID.startsWith('group_')) {
        groupID = conversationID.substring(6);
      }
      
      // Restore failed messages from persistence
      try {
        final currentToxId = await Prefs.getCurrentAccountToxId();
        final failedMessagesData = await Tim2ToxFailedMessagePersistence.loadFailedMessages(
          userID: userID,
          groupID: groupID,
          accountToxId: currentToxId,
        );
        
        if (failedMessagesData.isNotEmpty) {
          // Create a set of existing message IDs for quick lookup
          // FakeMessage only has msgID, not id
          final existingMsgIDs = hist.map((h) => h.msgID).whereType<String>().toSet();
          
          for (final failedMsgData in failedMessagesData) {
            final msgID = failedMsgData['msgID'] as String?;
            final id = failedMsgData['id'] as String?;
            
            // Check if message already exists in history
            // Check by msgID (FakeMessage only has msgID)
            bool messageExists = false;
            if (msgID != null && existingMsgIDs.contains(msgID)) {
              messageExists = true;
            } else if (id != null && existingMsgIDs.contains(id)) {
              // Also check if id matches msgID (some messages use id as msgID)
              messageExists = true;
            }
            
            // If message doesn't exist in history, add it as a failed message
            if (!messageExists && msgID != null) {
              // CRITICAL: For self-sent failed messages, fromUser should be selfId, not userID (receiver)
              // userID is the receiver (the other person), but fromUser should be the sender (self)
              final ffi = FakeUIKit.instance.im?.ffi;
              final selfId = ffi?.selfId ?? '';
              final isSelf = failedMsgData['isSelf'] as bool? ?? true;
              // For self-sent messages, fromUser should be selfId
              // For received messages, fromUser should be the sender (which would be in userID field)
              final fromUser = isSelf ? selfId : (failedMsgData['userID'] as String? ?? userID ?? '');
              // CRITICAL: Try to recover text content from history if it's empty in persistence
              // This handles the case where text was lost during persistence
              String text = failedMsgData['text'] as String? ?? '';
              if (text.isEmpty) {
                // Try to find the message in history by msgID to recover text
                try {
                  final historyMsg = hist.firstWhere((h) => h.msgID == msgID);
                  if (historyMsg.text.isNotEmpty) {
                    text = historyMsg.text;
                  }
                } catch (e) {
                  // Message not found in history, text remains empty
                }
              }
              
              // Add to history list as FakeMessage (will be converted to V2TimMessage below)
              hist.add(FakeMessage(
                msgID: msgID,
                conversationID: conversationID,
                fromUser: fromUser,
                text: text,
                timestampMs: (failedMsgData['timestamp'] as int? ?? (DateTime.now().millisecondsSinceEpoch / 1000).ceil()) * 1000,
                isPending: false,
                isReceived: true,
                isRead: false,
              ));
            }
          }
        }
      } catch (e) {
        // Ignore errors during failed message restoration
      }
      
      // Only clear and reload if we have history messages to load
      // If hist is empty, keep existing messages in buffer (they might not be saved yet)
      if (hist.isNotEmpty) {
        // Preserve messages in buffer that are not in history (e.g., failed messages that weren't saved)
        // These messages have temporary IDs like "created_temp_id-1" and won't be in history
        final historyMsgIDs = hist.map((h) => h.msgID).toSet();
        
        // Find messages in buffer that are not in history (failed messages, unsent messages, etc.)
        final messagesToPreserve = list.where((msg) {
          final msgID = msg.msgID;
          // Preserve messages with temporary IDs (created_temp_id-*) or messages not in history
          return msgID != null && 
                 (msgID.startsWith('created_temp_id-') || 
                  !historyMsgIDs.contains(msgID));
        }).toList();
        
        // Clear existing list and add history messages
        list.clear();
        V2TimMessage? latestMessage; // Track the latest message for conversation list update
        
        // Create a set of failed message IDs for quick lookup
        final failedMsgIDs = <String>{};
        final failedMsgDataMap = <String, Map<String, dynamic>>{};
        try {
          final currentToxId = await Prefs.getCurrentAccountToxId();
          final failedMessagesData = await Tim2ToxFailedMessagePersistence.loadFailedMessages(
            userID: userID,
            groupID: groupID,
            accountToxId: currentToxId,
          );
          for (final failedMsgData in failedMessagesData) {
            final msgID = failedMsgData['msgID'] as String?;
            final id = failedMsgData['id'] as String?;
            if (msgID != null) {
              failedMsgIDs.add(msgID);
              failedMsgDataMap[msgID] = failedMsgData;
            }
            if (id != null && id != msgID) {
              failedMsgIDs.add(id);
              failedMsgDataMap[id] = failedMsgData;
            }
          }
        } catch (e) {
          AppLogger.logError('[FakeChatMessageProvider] _loadHistoryForConversation: Error loading failed messages for status check: $e', e);
        }
        
        for (final h in hist) {
          final msg = _mapMsg(h);
          // If message status is SENDING (1), set it to FAIL (3) since client restarted
          // Messages that were sending when client restarted should be marked as failed
          if (msg.status == 1) {
            msg.status = 3; // V2TIM_MSG_STATUS_SEND_FAIL
          }
          // CRITICAL: Check if message is in failed messages list and restore failed status
          // This ensures that failed messages remain failed even after switching pages and reloading
          // History messages might have success status, but we trust the persistence
          final msgID = msg.msgID;
          final id = msg.id;
          if ((msgID != null && failedMsgIDs.contains(msgID)) || 
              (id != null && failedMsgIDs.contains(id))) {
            // Message is in failed list - mark as failed regardless of current status
            msg.status = MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL;
            // Also restore textElem if it's missing
            final failedMsgData = failedMsgDataMap[msgID ?? id ?? ''];
            if (failedMsgData != null && msg.textElem == null && 
                (msg.elemType == MessageElemType.V2TIM_ELEM_TYPE_TEXT || 
                 failedMsgData['elemType'] == MessageElemType.V2TIM_ELEM_TYPE_TEXT)) {
              final text = failedMsgData['text'] as String?;
              if (text != null && text.isNotEmpty) {
                msg.textElem = V2TimTextElem(text: text);
                msg.elemList.clear();
                msg.elemList.add(msg.textElem!);
              }
            }
          }
          list.add(msg);
          // Track the latest message (highest timestamp)
          if (latestMessage == null || (msg.timestamp ?? 0) > (latestMessage.timestamp ?? 0)) {
            latestMessage = msg;
          }
        }
        
        // Add back preserved messages (failed messages, unsent messages, etc.)
        list.addAll(messagesToPreserve);
        
        // Sort by timestamp ascending (oldest first, newest last)
        list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
        
        // IMPORTANT: Update conversation lastMessage after restoring failed messages
        // This ensures the latest message (including restored failed messages) appears in conversation list
        if (list.isNotEmpty) {
          // Find the actual latest message (after sorting)
          // The list is sorted by timestamp ascending, so the last element is the newest
          final actualLatestMessage = list.last;
          
          // CRITICAL: Check if there's a failed message in the list that is the latest
          // Failed messages should already be in the list (restored from persistence)
          // If the latest message is failed, we want to use it to update the conversation
          // Otherwise, we use the latest message (which might be a successful message)
          final messageToUse = actualLatestMessage;
          
          // Ensure userID and groupID are set for conversation identification
          if (messageToUse.userID == null && userID != null) {
            messageToUse.userID = userID;
          }
          if (messageToUse.groupID == null && groupID != null) {
            messageToUse.groupID = groupID;
          }
          
          // Trigger onReceiveNewMessage to update conversation list
          // This ensures the latest message (including failed messages) appears in the conversation list's second line
          TencentCloudChat.instance.dataInstance.messageData.onReceiveNewMessage(messageToUse);
        }
      } else {
        // If no history loaded, check if we have messages in buffer
        // If buffer is empty, this might be a new conversation or history hasn't loaded yet
        // Don't clear the buffer in this case - keep any existing messages
        // But still emit to stream to ensure UI is updated (even if empty)
      }
      
      // Always emit to stream, even if list is empty
      // This ensures UI is updated when history is loaded (or when no history exists)
      // UIKit's getMessageListForRender reverses the list, but our stream bypasses it
      // So we need to reverse the list before emitting to match UIKit's expected format
      // Reverse: newest first, oldest last (for reverse ListView, index 0 = newest at bottom)
      final ctrl = _ctrls[conversationID];
      if (ctrl != null && !ctrl.isClosed) {
        final reversedList = List<V2TimMessage>.from(list.reversed);
        ctrl.add(reversedList);
      }
    } catch (e) {
      // Ignore errors during history loading
    }
  }

  @override
  Future<void> sendText({String? userID, String? groupID, required String text}) async {
    final conv = (groupID != null && groupID.isNotEmpty) ? 'group_$groupID' : 'c2c_$userID';
    final mgr = FakeUIKit.instance.messageManager;
    if (mgr == null) {
      throw Exception("Message manager is not available");
    }
    
    // Check if friend is online BEFORE attempting to send (only for C2C, not groups)
    if (userID != null && groupID == null) {
      final ffi = FakeUIKit.instance.im?.ffi;
      if (ffi != null) {
        try {
          final friends = await ffi.getFriendList();
          final normalizedUserID = normalizeToxId(userID);
          final friend = friends.firstWhere(
            (f) => compareToxIds(f.userId, normalizedUserID),
            orElse: () => (userId: normalizedUserID, nickName: '', online: false, status: ''),
          );
          if (!friend.online) {
            // Friend is offline - throw exception so sendTextMessage can mark as failed immediately
            throw Exception("Friend is offline. Cannot send text.");
          }
        } catch (e) {
          // If it's the offline exception, re-throw it
          if (e.toString().contains('offline')) {
            rethrow;
          }
          // Continue with text send attempt if check fails for other reasons
        }
      }
    }
    
    // Friend is online (or group message) - try to send text
    try {
      await mgr.sendText(conv, text);
    } catch (e) {
      final errorMsg = e.toString();
      
      // If friend went offline between check and send, re-throw to let sendTextMessage handle
      if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
        // Only for C2C conversations (not groups)
        if (userID != null && groupID == null) {
          // Re-throw so sendTextMessage can mark as failed immediately
          rethrow;
        }
      }
      // For other errors or groups, re-throw to let UIKit handle
      rethrow;
    }
  }

  @override
  Future<void> sendImage({String? userID, String? groupID, required String imagePath, String? imageName}) async {
    final conv = (groupID != null && groupID.isNotEmpty) ? 'group_$groupID' : 'c2c_$userID';
    final mgr = FakeUIKit.instance.messageManager;
    if (mgr == null) {
      return;
    }
    
    // Check if friend is online BEFORE attempting to send (only for C2C, not groups)
    if (userID != null && groupID == null) {
      final ffi = FakeUIKit.instance.im?.ffi;
      if (ffi != null) {
        try {
          final friends = await ffi.getFriendList();
          final normalizedUserID = normalizeToxId(userID);
          final friend = friends.firstWhere(
            (f) => compareToxIds(f.userId, normalizedUserID),
            orElse: () => (userId: normalizedUserID, nickName: '', online: false, status: ''),
          );
          if (!friend.online) {
            // Friend is offline - throw exception so sendMessageFinalPhase can update message status
            throw Exception("Friend is offline. Cannot send file.");
          }
        } catch (e) {
          // If it's the offline exception, re-throw it
          if (e.toString().contains('offline')) {
            rethrow;
          }
          // Continue with image send attempt if check fails for other reasons
        }
      }
    }
    
    // Friend is online (or group message) - try to send image as file
    try {
      await mgr.sendFile(conv, imagePath);
    } catch (e) {
      final errorMsg = e.toString();
      
      // If friend went offline between check and send, re-throw to let sendMessageFinalPhase handle
      if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
        // Only for C2C conversations (not groups)
        if (userID != null && groupID == null) {
          // Re-throw so sendMessageFinalPhase can update message status
          rethrow;
        }
      }
      // For other errors or groups, re-throw to let UIKit handle
      rethrow;
    }
  }

  @override
  Future<void> sendFile({String? userID, String? groupID, required String filePath, String? fileName}) async {
    final conv = (groupID != null && groupID.isNotEmpty) ? 'group_$groupID' : 'c2c_$userID';
    final mgr = FakeUIKit.instance.messageManager;
    if (mgr == null) {
      return;
    }
    
    // Check if friend is online BEFORE attempting to send (only for C2C, not groups)
    if (userID != null && groupID == null) {
      final ffi = FakeUIKit.instance.im?.ffi;
      if (ffi != null) {
        try {
          final friends = await ffi.getFriendList();
          final normalizedUserID = normalizeToxId(userID);
          final friend = friends.firstWhere(
            (f) => compareToxIds(f.userId, normalizedUserID),
            orElse: () => (userId: normalizedUserID, nickName: '', online: false, status: ''),
          );
          if (!friend.online) {
            // Friend is offline - throw exception so sendMessageFinalPhase can update message status
            throw Exception("Friend is offline. Cannot send file.");
          }
        } catch (e) {
          // Continue with file send attempt if check fails
          // Re-throw if it's the offline exception
          if (e.toString().contains('offline')) {
            rethrow;
          }
        }
      }
    }
    
    // Friend is online (or group message) - try to send file
    try {
      await mgr.sendFile(conv, filePath);
    } catch (e) {
      final errorMsg = e.toString();
      
      // If friend went offline between check and send, re-throw to let sendMessageFinalPhase handle
      if (errorMsg.contains('offline') || errorMsg.contains('not connected')) {
        // Only for C2C conversations (not groups)
        if (userID != null && groupID == null) {
          // Re-throw so sendMessageFinalPhase can update message status
          rethrow;
        }
      }
      // For other errors or groups, re-throw to let UIKit handle
      rethrow;
    }
  }

  /// Find a message by msgID across all conversation buffers
  /// Also searches in FfiChatService history if not found in buffers
  /// Returns the message if found, null otherwise
  /// Update or add a message to the buffer and emit to stream
  /// This is used when messages are added/updated outside of FakeMessage events
  /// (e.g., when sendMessageFinalPhase updates message status to FAIL)
  void updateMessageInBuffer(V2TimMessage message, {String? userID, String? groupID}) {
    final conv = (groupID != null && groupID.isNotEmpty) ? 'group_$groupID' : 'c2c_$userID';
    if (conv.isEmpty) {
      return;
    }
    
    final list = _buffers.putIfAbsent(conv, () => <V2TimMessage>[]);
    
    // Check if message already exists by msgID or id
    final existingIndex = list.indexWhere((msg) => 
      (msg.msgID != null && msg.msgID == message.msgID) ||
      (msg.id != null && msg.id == message.id && message.id != null)
    );
    
    if (existingIndex >= 0) {
      // Message exists - update it
      list[existingIndex] = message;
    } else {
      // New message - add it
      list.add(message);
    }
    
    // Sort by timestamp ascending (oldest first, newest last)
    list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
    
    // Emit to stream (reversed for UIKit's expected format)
    final reversedList = List<V2TimMessage>.from(list.reversed);
    _ctrls[conv]?.add(reversedList);
    
    // CRITICAL: Emit FakeMessage event to trigger FakeProvider to update conversation lastMessage
    // This ensures that failed messages appear in the conversation list's second line
    // Only emit if message is failed (status == 3) to avoid duplicate events for normal messages
    if (message.status == MessageStatus.V2TIM_MSG_STATUS_SEND_FAIL) {
      try {
        final ffi = FakeUIKit.instance.im?.ffi;
        final selfId = ffi?.selfId ?? '';
        final isSelf = message.isSelf ?? false;
        final fromUser = isSelf ? selfId : (message.sender ?? message.userID ?? '');
        final text = message.textElem?.text ?? '';
        final timestampMs = (message.timestamp ?? 0) * 1000; // Convert seconds to milliseconds
        
        final fakeMsg = FakeMessage(
          msgID: message.msgID ?? message.id ?? '',
          conversationID: conv,
          fromUser: fromUser,
          text: text,
          timestampMs: timestampMs,
          filePath: message.fileElem?.path ?? message.imageElem?.path,
          fileName: message.fileElem?.fileName,
          mediaKind: message.imageElem != null ? 'image' : (message.fileElem != null ? 'file' : null),
          isPending: false, // Failed messages are not pending
          isReceived: false,
          isRead: false,
        );
        
        // Emit FakeMessage event to trigger FakeProvider to update conversation lastMessage
        FakeUIKit.instance.eventBusInstance.emit(FakeIM.topicMessage, fakeMsg);
      } catch (e) {
        // Ignore errors during FakeMessage event emission
      }
    }
  }

  V2TimMessage? findMessageByID(String msgID) {
    // First, try to find in _buffers (messages that have been loaded into chat windows)
    for (final entry in _buffers.entries) {
      try {
        final foundMessage = entry.value.firstWhere(
          (msg) => msg.msgID == msgID,
        );
        return foundMessage;
      } catch (e) {
        // Message not found in this conversation, continue searching
        continue;
      }
    }
    
    // If not found in buffers, try to find in FfiChatService history
    // This ensures historical messages that haven't been loaded into chat windows can still be found
    final ffi = FakeUIKit.instance.im?.ffi;
    if (ffi != null) {
      // Use FfiChatService's findUserIDAndGroupIDFromMsgID to locate the message
      final (userID, groupID) = ffi.findUserIDAndGroupIDFromMsgID(msgID);
      
      if (userID != null || groupID != null) {
        // Determine conversationID and actual ID
        String conversationID;
        String actualId;
        if (groupID != null) {
          conversationID = 'group_$groupID';
          actualId = groupID;
        } else {
          conversationID = 'c2c_$userID';
          actualId = userID!;
        }
        
        // Get history for this conversation
        final history = ffi.getHistory(actualId);
        // Search for the message in history
        try {
          final chatMsg = history.firstWhere((m) => m.msgID == msgID);
          // Found the ChatMessage, convert it to FakeMessage then to V2TimMessage
          final fakeMsg = FakeMessage(
            msgID: chatMsg.msgID ?? '${chatMsg.timestamp.millisecondsSinceEpoch}_${chatMsg.fromUserId}',
            conversationID: conversationID,
            fromUser: chatMsg.fromUserId,
            text: chatMsg.text,
            timestampMs: chatMsg.timestamp.millisecondsSinceEpoch,
            filePath: chatMsg.filePath,
            fileName: chatMsg.fileName,
            mediaKind: chatMsg.mediaKind,
            isPending: chatMsg.isPending,
            isReceived: chatMsg.isReceived,
            isRead: chatMsg.isRead,
          );
          // Convert FakeMessage to V2TimMessage using _mapMsg
          return _mapMsg(fakeMsg);
        } catch (e) {
          // Message not found in history (shouldn't happen if findUserIDAndGroupIDFromMsgID worked)
          return null;
        }
      }
    }
    
    return null;
  }

  @override
  Future<void> deleteMessages({String? userID, String? groupID, required List<String> msgIDs}) async {
    try {
      if (msgIDs.isEmpty) {
        return;
      }
      
      final conv = (groupID != null && groupID.isNotEmpty) ? 'group_$groupID' : 'c2c_$userID';
      
      if (conv.isEmpty || (userID == null && groupID == null)) {
        throw Exception('Invalid conversation: userID and groupID cannot both be null');
      }
      
      // Remove messages from buffer
      _removeMessagesFromBuffer(conv, msgIDs);
      
      // Delete messages from history via FakeMessageManager
      final mgr = FakeUIKit.instance.messageManager;
      if (mgr != null) {
        await mgr.deleteMessages(msgIDs);
      } else {
        throw Exception('MessageManager is not available');
      }
    } catch (e) {
      // Re-throw the exception so UIKit knows the provider failed
      rethrow;
    }
  }

  void _listenForMessageDeletions() {
    // Listen to UIKit's message data updates to detect deletions
    // When UIKit deletes messages, it updates the message list, and we need to sync our buffers
    // This is a workaround since UIKit calls SDK directly, not through provider
    // We'll periodically check for deletions by comparing message lists
    // Note: This is not ideal, but it's the best we can do without modifying UIKit
    // A better solution would be to intercept SDK calls, but that requires modifying UIKit code
  }

  /// Remove messages from buffer by their IDs
  /// This is called when messages are deleted
  void _removeMessagesFromBuffer(String conversationID, List<String> msgIDs) {
    final list = _buffers[conversationID];
    if (list == null) {
      return;
    }
    
    list.removeWhere((msg) {
      final msgID = msg.msgID ?? '';
      // Also check id field as fallback
      final id = msg.id ?? '';
      return msgIDs.contains(msgID) || (id.isNotEmpty && msgIDs.contains(id));
    });
    
    // Re-sort after removal
    list.sort((a, b) => (a.timestamp ?? 0).compareTo(b.timestamp ?? 0));
    // Emit updated list to stream
    final ctrl = _ctrls[conversationID];
    if (ctrl != null && !ctrl.isClosed) {
      final reversedList = List<V2TimMessage>.from(list.reversed);
      ctrl.add(reversedList);
    }
  }

  /// Clear message buffer for a conversation and notify UI
  /// This is called when chat history is cleared
  void clearMessageBuffer(String conversationID) {
    // Clear the buffer (remove or clear the list)
    if (_buffers.containsKey(conversationID)) {
      _buffers[conversationID]!.clear();
      _buffers.remove(conversationID);
    }
    // Emit empty list to stream to notify UI (if stream controller exists)
    final ctrl = _ctrls[conversationID];
    if (ctrl != null && !ctrl.isClosed) {
      ctrl.add(<V2TimMessage>[]);
    }
  }

  void dispose() {
    _sub?.cancel();
    for (final c in _ctrls.values) {
      c.close();
    }
    _ctrls.clear();
    _buffers.clear();
    _cachedSelfAvatarPath = null;
    _cachedFriendAvatars.clear();
    _fileProgress.clear();
  }
}

