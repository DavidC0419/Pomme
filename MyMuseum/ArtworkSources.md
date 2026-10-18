# Artwork Sources

- Device renders in `Assets.xcassets` were matched to collection product identifiers and model numbers using AppleDB metadata and the `littlebyteorg/apple-device-images` image repository.
- The image repository documents PNG artwork at multiple resolutions: https://github.com/littlebyteorg/apple-device-images
- In addition to the collection images, 808 256px renders are bundled for 808 of 1,246 unique image keys in the searchable catalog. The remaining keys had no image at the checked source endpoint; those devices continue to use a category illustration.
- Search-result and collection images are stored locally in the app bundle, so showing them does not require a network connection.
- The image repository does not state an explicit license for its artwork. Verify image rights before distributing the app; AppleDB’s metadata license does not establish rights to these image files.
- Added 43 verified color-specific renders for owned iPod touch, iPhone 5c, SE, 8 Plus, 11 Pro, 13 mini, and 14 Pro Max models. Color options are shown only when the matching local color render exists; unsupported historical variants remain on their neutral catalog artwork rather than receiving a fake tint.
