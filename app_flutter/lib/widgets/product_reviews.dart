import 'package:flutter/material.dart';

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/reviews_service.dart';
import 'common.dart';

class ProductReviews extends StatefulWidget {
  const ProductReviews({super.key, required this.productId});
  final int productId;
  @override
  State<ProductReviews> createState() => _ProductReviewsState();
}

class _ProductReviewsState extends State<ProductReviews> {
  List<SFProductReview> _reviews = [];
  SFProductRating _rating = const SFProductRating(average: 0, count: 0);
  Map<int, int> _breakdown = {};
  bool _loading = true, _busy = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more) setState(() => _busy = true);
    try {
      final results = await Future.wait([
        SFReviews.loadReviews(
          widget.productId,
          offset: more ? _reviews.length : 0,
        ),
        SFReviews.loadRatings([widget.productId]),
        SFReviews.loadBreakdown(widget.productId),
      ]);
      if (!mounted) return;
      setState(() {
        final rows = results[0] as List<SFProductReview>;
        _reviews = more ? [..._reviews, ...rows] : rows;
        _rating =
            (results[1] as Map<int, SFProductRating>)[widget.productId] ??
            const SFProductRating(average: 0, count: 0);
        _breakdown = results[2] as Map<int, int>;
        _loading = false;
        _busy = false;
        _error = null;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
          _busy = false;
        });
      }
    }
  }

  Future<void> _writeReview() async {
    if (!AuthService.instance.isSignedIn) {
      showSFMessage(context, context.t('review_login_first'));
      return;
    }
    setState(() => _busy = true);
    try {
      final existing = await SFReviews.myReview(widget.productId);
      if (!mounted) return;
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) =>
            _ReviewDialog(productId: widget.productId, existing: existing),
      );
      if (saved == true) await _load();
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SFProductReview review) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(context.t('review_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('msg_cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('review_delete')),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _busy = true);
    try {
      if (!await SFReviews.deleteReview(review.id)) {
        throw Exception('تعذّر حذف المراجعة');
      }
      await _load();
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;
    if (_loading) return const LinearProgressIndicator();
    if (_error != null) {
      return SFStateView(message: i18n.t('fx_failed'), onRetry: _load);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          i18n.t('reviews_title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Text(
          '${_rating.average.toStringAsFixed(1)} ★ (${_rating.count})',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800),
        ),
        for (var star = 5; star >= 1; star--)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text('$star ★'),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(
                    value: _rating.count == 0
                        ? 0
                        : ((_breakdown[star] ?? 0) / _rating.count).clamp(0, 1),
                    backgroundColor: SFColors.border,
                    color: SFColors.gold,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(width: 25, child: Text('${_breakdown[star] ?? 0}')),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _writeReview,
          icon: const Icon(Icons.rate_review_outlined),
          label: Text(i18n.t('review_write')),
        ),
        if (_reviews.isEmpty) Text(i18n.t('reviews_none')),
        for (final review in _reviews)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SFImage(
                        url: review.authorImage,
                        width: 32,
                        height: 32,
                        radius: 99,
                        placeholderIcon: Icons.person_outline,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(review.authorName)),
                      Text(
                        '${review.rating} ★',
                        style: const TextStyle(color: SFColors.midGreen),
                      ),
                    ],
                  ),
                  if (review.isVerified)
                    Text(
                      i18n.t('review_verified_buyer'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: SFColors.midGreen,
                      ),
                    ),
                  if (review.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(review.body),
                    ),
                  if (review.isMine)
                    Wrap(
                      children: [
                        TextButton(
                          onPressed: _busy ? null : _writeReview,
                          child: Text(i18n.t('review_edit')),
                        ),
                        TextButton(
                          onPressed: _busy ? null : () => _delete(review),
                          child: Text(i18n.t('review_delete')),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        if (_reviews.length < _rating.count)
          TextButton(
            onPressed: _busy ? null : () => _load(more: true),
            child: Text(i18n.t('review_show_more')),
          ),
      ],
    );
  }
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog({required this.productId, this.existing});
  final int productId;
  final SFProductReview? existing;
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  late final TextEditingController _body = TextEditingController(
    text: widget.existing?.body ?? '',
  );
  late int _stars = widget.existing?.rating ?? 0;
  bool _saving = false;
  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SFReviews.submitReview(widget.productId, _stars, _body.text);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.t('review_your_rating')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() => _stars = star),
                  icon: Icon(
                    star <= _stars ? Icons.star : Icons.star_border,
                    color: SFColors.gold,
                  ),
                  tooltip: '$star',
                ),
            ],
          ),
          TextField(
            controller: _body,
            maxLength: 2000,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: context.t('review_placeholder'),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: Text(context.t('msg_cancel')),
      ),
      FilledButton(
        onPressed: _saving || _stars == 0 ? null : _save,
        child: Text(context.t(_saving ? 'review_sending' : 'review_submit')),
      ),
    ],
  );
}
