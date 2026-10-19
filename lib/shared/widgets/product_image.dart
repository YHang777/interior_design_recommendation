import 'dart:io' show File;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/product.dart';

class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    this.product,
    this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorIconSize = 24,
  });

  final Product? product;
  final String? imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final double errorIconSize;

  String get _url =>
      imageUrl ??
      product?.image ??
      (product?.resolvedImages.isNotEmpty ?? false
          ? product!.resolvedImages.first
          : '');

  bool get _isNetwork => _url.startsWith('http');

  bool get _isLocalFile => _url.startsWith('/');

  @override
  Widget build(BuildContext context) {
    if (_url.isEmpty) return _errorBox();

    if (_isNetwork) {
      return CachedNetworkImage(
        imageUrl: _url,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => _placeholderBox(),
        errorWidget: (_, __, ___) => _errorBox(),
      );
    }
    if (_isLocalFile) {
      return Image.file(
        File(_url),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _errorBox(),
      );
    }
    return Image.asset(
      _url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => _errorBox(),
    );
  }

  Widget _placeholderBox() {
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceContainer,
      alignment: Alignment.center,
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.textHint,
        ),
      ),
    );
  }

  Widget _errorBox() {
    return Container(
      width: width,
      height: height,
      color: AppColors.surfaceContainer,
      alignment: Alignment.center,
      child: Icon(Icons.image, size: errorIconSize, color: AppColors.textHint),
    );
  }
}
