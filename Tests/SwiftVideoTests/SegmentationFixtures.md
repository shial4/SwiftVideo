<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Segmentation fixtures

`Resources/Milestone/person.png` is an original AI-generated image of a fictional adult, created November 10, 2026 with the built-in image generation tool. Software Deck Pty Ltd provides it under this repository's Apache 2.0 license. It checks retention of the yellow-shirt foreground and removal of the blue background. It is one controlled sample, not a model-quality benchmark or evidence of demographic coverage.

The generation prompt was:

> Use case: photorealistic-natural. Asset type: small deterministic test fixture for a video library's person-segmentation integration tests. Create a square, photorealistic studio photograph of one fictional adult person, facing the camera, visible from head to waist, centered with generous clear space above the head and at both sides. A simple solid mustard-yellow long-sleeve shirt, dark short hair, natural skin, relaxed neutral expression. The shirt and torso fill the lower center of the image. Behind them is a flat, evenly lit mid-blue studio backdrop with no furniture, objects, text, logos or shadows. Sharp clear silhouette, natural realistic face and anatomy, no motion blur, no depth-of-field blur, no watermark, no frame. The entire background must be visible at the four corners. Opaque image, not a cutout.

`Resources/Milestone/selfie_segmenter.tflite` is Google's MediaPipe Selfie Segmenter square float16 model, version 1. It is a test-only asset and is not bundled in the library product. Applications supply their own local model URL. The [model card](https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Selfie%20Segmentation.pdf) identifies Apache 2.0 licensing and authors Tingbo Hou, Siargey Pisarchyk and Karthik Raveendran. Retain the [license text](../../Documentation/ThirdParty/mediapipe-LICENSE.txt) when distributing it.

- Source: [pinned model version](https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite).
- Size: 249,537 bytes.
- SHA-256: `191ac9529ae506ee0beefa6b2c945a172dab9d07d1e802a290a4e4038226658b`.

`Resources/Milestone/DeepLabV3FP16.mlmodel` is the Core ML model version 1.3 published in [Apple's model catalogue](https://developer.apple.com/machine-learning/models/). Its embedded license metadata points to TensorFlow's Apache 2.0 license and the original [DeepLab source](https://github.com/tensorflow/models/tree/master/research/deeplab). The complete [TensorFlow license and bundled notices](../../Documentation/ThirdParty/tensorflow-LICENSE.txt) are retained. Authors recorded in the model are Mark Sandler, Andrew Howard, Menglong Zhu, Andrey Zhmoginov, Liang-Chieh Chen, Yukun Zhu, George Papandreou, Florian Schroff and Hartwig Adam. This is a test-only asset, not a library resource.

- Source: [DeepLabV3FP16 model](https://ml-assets.apple.com/coreml/models/Image/ImageSegmentation/DeepLabV3/DeepLabV3FP16.mlmodel).
- Size: 4,342,971 bytes.
- SHA-256: `6c2c8cbe1c2d765f231408458b8c273976039ae04a05b112d748fc21cb3bfe95`.
- Contract: `image` 513x513; `semanticPredictions` Int32 513x513; person class 15.

Tests render only six frames at 320x180. The video case first encodes the portrait through the public exporter and then applies segmentation to decoded video frames. The portrait is intentionally not a precomputed mask, so both inference and compositing must work for the test to pass. macOS tests also run the system Vision model. Android emulator tests explicitly select CPU inference because its GL translator rejects the MediaPipe GPU delegate's SSBO query; GPU compositing remains active.
