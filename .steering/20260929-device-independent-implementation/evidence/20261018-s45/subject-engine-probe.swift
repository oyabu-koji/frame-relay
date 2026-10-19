import CoreImage

import Foundation
import AVFoundation
import CoreGraphics
import ImageIO
import Vision
import CoreML
import CryptoKit

@main enum Probe {
 static func image(_ name: String) throws -> CGImage {
  let url = URL(fileURLWithPath: "/private/tmp/fr-s45-20261018-ow_sx8bp/fixtures/" + name + ".jpg")
  return CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithURL(url as CFURL, nil)!,0,nil)!
 }
 static func buffer(_ image: CGImage?) throws -> CVPixelBuffer {
  var value: CVPixelBuffer?
  precondition(CVPixelBufferCreate(kCFAllocatorDefault,512,640,kCVPixelFormatType_32BGRA,[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true] as CFDictionary,&value) == kCVReturnSuccess)
  let result=value!
  CVPixelBufferLockBaseAddress(result,[])
  let context=CGContext(data:CVPixelBufferGetBaseAddress(result),width:512,height:640,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(result),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue|CGBitmapInfo.byteOrder32Little.rawValue)!
  context.setFillColor(CGColor(gray:0.4,alpha:1)); context.fill(CGRect(x:0,y:0,width:512,height:640))
  if let image { context.draw(image,in:CGRect(x:0,y:0,width:512,height:640)) }
  CVPixelBufferUnlockBaseAddress(result,[])
  return result
 }
 static func configure(_ request: VNRequest, cpu:Bool) throws {
  if cpu {for(stage,devices) in try request.supportedComputeStageDevices {let device=devices.first {if case .cpu = $0{return true};return false};request.setComputeDevice(device,for:stage)}}
 }
 static func feature(_ buffer:CVPixelBuffer,cpu:Bool) throws -> VNFeaturePrintObservation {
  let handler=VNImageRequestHandler(cvPixelBuffer:buffer,orientation:.up)
  let detection=VNDetectHumanRectanglesRequest();detection.upperBodyOnly=true;try configure(detection,cpu:cpu);try handler.perform([detection]);let observation=detection.results!.first!
  let bounds=observation.boundingBox.intersection(CGRect(x:0,y:0,width:1,height:1));print("DETECTION",cpu,observation.confidence,bounds)
  let feature=VNGenerateImageFeaturePrintRequest();feature.revision=VNGenerateImageFeaturePrintRequestRevision2;feature.regionOfInterest=bounds;feature.imageCropAndScaleOption = .scaleFit;try configure(feature,cpu:cpu);try handler.perform([feature]);return feature.results!.first!
 }
 static func main() throws {
  let sally=try buffer(image("sally-ride-1979")),mae=try buffer(image("mae-jemison-1987")),blank=try buffer(nil)
  for(name,buffer) in [("sally",sally),("mae",mae),("blank",blank)] {
   CVPixelBufferLockBaseAddress(buffer,.readOnly)
   let data=Data(bytes:CVPixelBufferGetBaseAddress(buffer)!,count:CVPixelBufferGetDataSize(buffer));print("PIXELS",name,SHA256.hash(data:data),data.count)
   CVPixelBufferUnlockBaseAddress(buffer,.readOnly)
   let context=CIContext();let image=context.createCGImage(CIImage(cvPixelBuffer:buffer),from:CGRect(x:0,y:0,width:512,height:640))!;let dest=CGImageDestinationCreateWithURL(URL(fileURLWithPath:"/private/tmp/fr-s45-20261018-ow_sx8bp/"+name+"-buffer.png") as CFURL,"public.png" as CFString,1,nil)!;CGImageDestinationAddImage(dest,image,nil);CGImageDestinationFinalize(dest)
  }
  for cpu in [false,true] {let first=try feature(sally,cpu:cpu),second=try feature(mae,cpu:cpu);print("FEATURE DISTANCE",cpu,try NativeSubjectVisionEngine.distance(first,second))}
  let policy=CaptureSubjectPolicy(version:"probe",lostGrace:3,noPersonFocus:.tapPosition);let engine=NativeSubjectVisionEngine(policy:policy)
  let ctx=CaptureSubjectContext(generation:.init(session:.init(rawValue:"probe"),settings:1),framingRevision:1,selectionRevision:0)
  let initial=try engine.process(sally,instruction:.init(context:ctx,protagonist:nil,allowsReacquisition:true),sequence:1,observedAt:1)
  print("INITIAL",initial.candidates)
  let selected=initial.candidates.first!.id
  let instruction=NativeSubjectAnalysisInstruction(context:.init(generation:ctx.generation,framingRevision:1,selectionRevision:1),protagonist:selected,allowsReacquisition:true)
  for(index,buffer) in [sally,blank,mae,sally].enumerated(){let result=try engine.process(buffer,instruction:instruction,sequence:UInt64(index+2),observedAt:1.2+Double(index)*0.2);print("RESULT",index,result.candidates,result.available)}
 }
}
