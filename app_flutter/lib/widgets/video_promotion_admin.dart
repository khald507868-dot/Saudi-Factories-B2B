import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/video_promotion_service.dart';
import '../services/upload_service.dart';
import 'common.dart';
import 'home_video_promotions.dart';

/// إدارة إعلانات الرئيسية؛ صلاحيات الكتابة تُفرض أيضاً في الخادم.
class VideoPromotionAdmin extends StatefulWidget {
  const VideoPromotionAdmin({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<VideoPromotionAdmin> createState() => _VideoPromotionAdminState();
}

class _VideoPromotionAdminState extends State<VideoPromotionAdmin> {
  Future<List<SFVideoPromotion>>? _future;
  final Set<String> _busy = {};

  bool get _isAdmin => AuthService.instance.profile?.isAdmin == true;

  @override
  void initState() {
    super.initState();
    if (_isAdmin) _future = VideoPromotionService.listAdmin();
    AuthService.instance.addListener(_authChanged);
  }

  void _authChanged() {
    if (!mounted) return;
    setState(() {
      if (!_isAdmin) {
        _future = null;
      } else {
        _future ??= VideoPromotionService.listAdmin();
      }
    });
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_authChanged);
    super.dispose();
  }

  Future<void> _reload() async {
    if (!_isAdmin || !mounted) return;
    final request = VideoPromotionService.listAdmin();
    setState(() {
      _future = request;
    });
    try {
      await request;
    } catch (_) {
      // FutureBuilder يعرض الخطأ وزر المحاولة من دون إخفاء الصفحة.
    }
  }

  Future<void> _edit([SFVideoPromotion? existing]) async {
    if (!_isAdmin) return;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _VideoPromotionEditor(existing: existing),
      ),
    );
    if (changed != true || !mounted) return;
    widget.onChanged?.call();
    await _reload();
  }

  Future<void> _setActive(SFVideoPromotion promotion, bool value) async {
    if (!_isAdmin || _busy.contains(promotion.id)) return;
    setState(() => _busy.add(promotion.id));
    try {
      await VideoPromotionService.setActive(promotion, value);
      if (!mounted) return;
      widget.onChanged?.call();
      await _reload();
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(promotion.id));
    }
  }

  Future<void> _delete(SFVideoPromotion promotion) async {
    if (!_isAdmin || _busy.contains(promotion.id)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.t('promo_delete')),
        content: Text(context.t('promo_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.t('msg_cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SFColors.danger),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.t('promo_delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_isAdmin) return;
    setState(() => _busy.add(promotion.id));
    try {
      await VideoPromotionService.delete(promotion);
      if (!mounted) return;
      showSFMessage(context, context.t('promo_deleted'));
      widget.onChanged?.call();
      await _reload();
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(promotion.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return SFStateView(
        message: context.t('promo_admin_only'),
        icon: Icons.lock_outline,
      );
    }
    return FutureBuilder<List<SFVideoPromotion>>(
      future: _future,
      builder: (context, snapshot) {
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final promotions = snapshot.data ?? const <SFVideoPromotion>[];
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                context.t('video_ads_admin_hint'),
                style: const TextStyle(color: SFColors.muted2, height: 1.6),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: ready ? () => _edit() : null,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(context.t('video_ads_add')),
              ),
              const SizedBox(height: 16),
              if (snapshot.connectionState != ConnectionState.done)
                SFStateView(message: context.t('fx_loading'), loading: true)
              else if (snapshot.hasError)
                SFStateView(
                  message: context.t('video_ads_unavailable'),
                  icon: Icons.cloud_off_outlined,
                  onRetry: _reload,
                  retryLabel: context.t('app_retry'),
                )
              else if (promotions.isEmpty)
                SFStateView(
                  message: context.t('video_ads_empty'),
                  icon: Icons.campaign_outlined,
                )
              else
                for (final promotion in promotions) ...[
                  _card(promotion),
                  const SizedBox(height: 14),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _card(SFVideoPromotion promotion) {
    final busy = _busy.contains(promotion.id);
    return Container(
      decoration: BoxDecoration(
        color: SFColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SFColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PromotionImage(url: promotion.imageUrl),
          const SizedBox(height: 12),
          Text(
            promotion.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            '${context.t('promo_order')}: ${promotion.sortOrder}',
            style: const TextStyle(color: SFColors.muted2, fontSize: 12),
          ),
          Material(
            color: Colors.transparent,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(
                context.t(
                  promotion.isActive ? 'promo_visible' : 'promo_hidden',
                ),
              ),
              value: promotion.isActive,
              onChanged: busy ? null : (value) => _setActive(promotion, value),
            ),
          ),
          if (busy)
            const LinearProgressIndicator(minHeight: 2)
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VideoAdPlayer(ad: promotion),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(context.t('video_ads_play')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _edit(promotion),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(context.t('video_ads_edit')),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: SFColors.danger),
                  onPressed: () => _delete(promotion),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: Text(context.t('promo_delete')),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _VideoPromotionEditor extends StatefulWidget {
  const _VideoPromotionEditor({this.existing});

  final SFVideoPromotion? existing;

  @override
  State<_VideoPromotionEditor> createState() => _VideoPromotionEditorState();
}

class _VideoPromotionEditorState extends State<_VideoPromotionEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _target;
  late final TextEditingController _order;
  late String _imageUrl;
  late String _videoUrl;
  late String _logoUrl;
  late bool _isActive;
  final Set<String> _pendingImages = {};
  bool _uploading = false;
  bool _saving = false;
  String? _imageError;
  String? _saveError;

  bool get _busy => _uploading || _saving;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _title = TextEditingController(text: existing?.title ?? '');
    _target = TextEditingController(text: existing?.targetUrl ?? '');
    _order = TextEditingController(text: '${existing?.sortOrder ?? 0}');
    _imageUrl = existing?.imageUrl ?? '';
    _videoUrl = existing?.videoUrl ?? '';
    _logoUrl = existing?.logoUrl ?? '';
    _isActive = existing?.isActive ?? true;
  }

  /// نزيل الصور الجديدة المهملة فقط؛ الخدمة تتحقق من الملكية وعدم استخدامها.
  Future<void> _discard(String url) async {
    try {
      await VideoPromotionService.cleanupUploadedImage(url);
      _pendingImages.remove(url);
    } catch (_) {
      // فشل تنظيف صورة مؤقتة لا يغيّر نجاح حفظ الإعلان أو يمنع الإغلاق.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _order.dispose();
    for (final url in _pendingImages.toList()) {
      unawaited(_discard(url));
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_busy || AuthService.instance.profile?.isAdmin != true) return;
    setState(() => _uploading = true);
    try {
      final url = await SFUpload.pickAndUploadImage(
        bucket: VideoPromotionService.bucket,
        folder: 'banners',
        maxSize: 1600,
      );
      if (url == null) return;
      _pendingImages.add(url);
      if (!mounted) {
        await _discard(url);
        return;
      }
      final previous = _imageUrl;
      setState(() {
        _imageUrl = url;
        _imageError = null;
      });
      if (_pendingImages.contains(previous)) await _discard(previous);
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickMedia({required bool video}) async {
    if (_busy || AuthService.instance.profile?.isAdmin != true) return;
    setState(() => _uploading = true);
    try {
      final url = video
          ? await SFUpload.pickAndUploadVideo(
              bucket: VideoPromotionService.bucket,
            )
          : await SFUpload.pickAndUploadImage(
              bucket: VideoPromotionService.bucket,
              folder: 'logos',
              maxSize: 256,
            );
      if (url == null) return;
      _pendingImages.add(url);
      if (!mounted) {
        await _discard(url);
        return;
      }
      final previous = video ? _videoUrl : _logoUrl;
      setState(() {
        if (video) {
          _videoUrl = url;
        } else {
          _logoUrl = url;
        }
        _saveError = null;
      });
      if (_pendingImages.contains(previous)) await _discard(previous);
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_busy || AuthService.instance.profile?.isAdmin != true) return;
    final valid = _formKey.currentState!.validate();
    setState(() {
      _imageError = _imageUrl.isEmpty
          ? context.t('promo_image_required')
          : null;
      _saveError = null;
    });
    if (_videoUrl.isEmpty) {
      setState(() => _saveError = context.t('video_ads_required'));
      return;
    }
    if (!valid || _imageError != null) return;
    setState(() => _saving = true);
    try {
      final saved = await VideoPromotionService.save(
        existing: widget.existing,
        title: _title.text.trim(),
        imageUrl: _imageUrl,
        videoUrl: _videoUrl,
        logoUrl: _logoUrl,
        targetUrl: _target.text.trim(),
        isActive: _isActive,
        sortOrder: int.parse(_order.text),
      );
      // الصورة أصبحت مرتبطة بالإعلان: لا تُحذف عند تحرير النموذج.
      _pendingImages.removeAll([saved.imageUrl, saved.videoUrl, saved.logoUrl]);
      if (!mounted) return;
      setState(() => _saving = false);
      // تحديث PopScope قبل إغلاق الصفحة بعد نجاح الحفظ.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      showSFMessage(context, context.t('promo_saved'));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      final key = error is FormatException
          ? switch (error.message) {
              'video_required' => 'video_ads_required',
              'logo_invalid' => 'promo_image_required',
              'promotion_title_invalid' => 'promo_title_required',
              'promotion_image_required' => 'promo_image_required',
              'promotion_link_invalid' => 'promo_target_invalid',
              'promotion_order_invalid' => 'promo_order_invalid',
              _ => 'admin_action_failed',
            }
          : 'admin_action_failed';
      setState(() => _saveError = context.t(key));
      if (error is! FormatException) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthService.instance,
    builder: (context, _) => PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: SFTopBar(
          title: context.t(
            widget.existing == null ? 'video_ads_add' : 'video_ads_edit',
          ),
          showBack: true,
        ),
        body: AuthService.instance.profile?.isAdmin != true
            ? SFStateView(
                message: context.t('promo_admin_only'),
                icon: Icons.lock_outline,
              )
            : SafeArea(
                top: false,
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        context.t('video_ads_cover'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 10),
                      _PromotionImage(url: _imageUrl),
                      const SizedBox(height: 10),
                      Text(
                        context.t('video_ads_cover_hint'),
                        style: const TextStyle(color: SFColors.muted2),
                      ),
                      _imageError == null
                          ? const SizedBox.shrink()
                          : Text(
                              _imageError!,
                              style: const TextStyle(color: SFColors.danger),
                            ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _pickImage,
                        icon: _uploading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          context.t(
                            _uploading
                                ? 'msg_uploading'
                                : _imageUrl.isEmpty
                                ? 'promo_upload'
                                : 'promo_replace_image',
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(context.t('video_ads_video_hint')),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _pickMedia(video: true),
                        icon: Icon(
                          _videoUrl.isEmpty
                              ? Icons.video_library_outlined
                              : Icons.check_circle_outline,
                        ),
                        label: Text(
                          context.t(
                            _videoUrl.isEmpty
                                ? 'video_ads_upload'
                                : 'video_ads_replace',
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_logoUrl.isNotEmpty)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: SFImage(url: _logoUrl, width: 48, height: 48),
                        ),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _pickMedia(video: false),
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(context.t('video_ads_logo')),
                      ),
                      if (_logoUrl.isNotEmpty)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => setState(() => _logoUrl = ''),
                          child: Text(context.t('video_ads_remove_logo')),
                        ),
                      const SizedBox(height: 22),
                      TextFormField(
                        key: const ValueKey('promotion-title'),
                        controller: _title,
                        enabled: !_busy,
                        maxLength: 120,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.t('promo_title'),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? context.t('promo_title_required')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: const ValueKey('promotion-target'),
                        controller: _target,
                        enabled: !_busy,
                        maxLength: 2048,
                        keyboardType: TextInputType.url,
                        textDirection: TextDirection.ltr,
                        autocorrect: false,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: context.t('promo_target'),
                          hintText: 'https://',
                          counterText: '',
                        ),
                        validator: (value) =>
                            SFVideoPromotion.isValidTargetUrl(
                              value?.trim() ?? '',
                            )
                            ? null
                            : context.t('promo_target_invalid'),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        key: const ValueKey('promotion-order'),
                        controller: _order,
                        enabled: !_busy,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 4,
                        decoration: InputDecoration(
                          labelText: context.t('promo_order'),
                          helperText: context.t('promo_order_hint'),
                          counterText: '',
                        ),
                        validator: (value) {
                          final order = int.tryParse(value ?? '');
                          return order == null || order < 0 || order > 9999
                              ? context.t('promo_order_invalid')
                              : null;
                        },
                      ),
                      const SizedBox(height: 12),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(context.t('promo_visible')),
                        value: _isActive,
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _isActive = value),
                      ),
                      const SizedBox(height: 16),
                      if (_saveError != null) ...[
                        Text(
                          _saveError!,
                          style: const TextStyle(color: SFColors.danger),
                        ),
                        const SizedBox(height: 8),
                      ],
                      FilledButton.icon(
                        onPressed: _busy ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: SFColors.white,
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(context.t('promo_save')),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: Text(context.t('msg_cancel')),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    ),
  );
}

class _PromotionImage extends StatelessWidget {
  const _PromotionImage({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) => Center(
    child: SizedBox(
      width: 140,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: SFColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SFColors.border),
          ),
          child: SFImage(
            url: url,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            placeholderIcon: Icons.campaign_outlined,
          ),
        ),
      ),
    ),
  );
}
