// ============================================================
//  صفحة المصنع — مقابل app-factory.html
//
//  قرار التحرير يأتي من الخادم: owner_id == المستخدم الحالي.
//  لا يُقرأ من تخزين الجهاز، فذاك قابل للتزوير. وحتى لو ظهرت
//  واجهة التحرير خطأً، سياسات RLS ترفض الكتابة على مصنع الغير.
//
//  التبويبات تُبدّل المحتوى ولا تُمرّر إليه — والرئيسية تجمع
//  النبذة والمنشورات معاً، وهو المطلوب.
// ============================================================

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/i18n.dart';
import '../core/i18n_data.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/factory_service.dart';
import '../services/catalog_service.dart';
import '../services/messages_service.dart';
import '../widgets/common.dart';
import '../widgets/catalog_product_card.dart';
import 'chat_page.dart';
import 'factory_edit_page.dart';
import 'factories_page.dart';
import 'auth_page.dart';

class FactoryPage extends StatefulWidget {
  const FactoryPage({super.key, required this.factoryId});

  final int factoryId;

  @override
  State<FactoryPage> createState() => _FactoryPageState();
}

class _FactoryPageState extends State<FactoryPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  SFFactory? _factory;
  List<SFProduct> _products = [];
  List<SFPost> _posts = [];
  bool _loading = true;
  Object? _error;
  SFFollowState? _follows;
  bool _followBusy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final f = await FactoryService.byId(widget.factoryId);
      if (f == null) {
        if (mounted) {
          setState(() {
            _factory = null;
            _loading = false;
          });
        }
        return;
      }
      final results = await Future.wait([
        FactoryService.products(widget.factoryId),
        FactoryService.posts(widget.factoryId),
      ]);
      SFFollowState? follows;
      try {
        follows = await CatalogService.follows(f.id);
      } catch (_) {
        /* غياب العدّاد لا يمنع قراءة الصفحة. */
      }
      if (!mounted) return;
      setState(() {
        _factory = f;
        _products = (results[0] as List<SFProduct>)
            .map(
              (p) => SFProduct({
                ...p.raw,
                'factories': {'name': f.name, 'status': f.status},
              }),
            )
            .toList();
        _posts = results[1] as List<SFPost>;
        _follows = follows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _follow() async {
    final factory = _factory;
    if (factory == null || factory.isMine || _followBusy) return;
    if (!AuthService.instance.isSignedIn) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const AuthPage(accountType: 'individual'),
        ),
      );
      if (!mounted || !AuthService.instance.isSignedIn) return;
      await _load();
      return;
    }
    setState(() => _followBusy = true);
    try {
      final state = await CatalogService.setFollowing(
        factory,
        !(_follows?.isFollowing ?? false),
      );
      if (mounted) setState(() => _follows = state);
    } catch (error) {
      if (mounted) showSFError(context, error);
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _visitWebsite() async {
    final uri = _factory?.websiteUri;
    if (uri == null) return;
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        showSFError(context, Exception(context.t('factory_open_link_failed')));
      }
    } catch (error) {
      if (mounted) showSFError(context, error);
    }
  }

  Future<void> _contact() async {
    final f = _factory;
    if (f == null) return;

    if (!AuthService.instance.isSignedIn) {
      showSFError(context, Exception('يجب تسجيل الدخول للمراسلة'));
      return;
    }
    try {
      final thread = await SFMessages.ensureFactoryConversation(f.id);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatPage(
            conversationId: thread.conversationId,
            title: thread.name.isEmpty ? f.name : thread.name,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showSFError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(i18n.t('factory_page_heading'))),
        body: SFStateView(message: i18n.t('fx_loading'), loading: true),
      );
    }

    final f = _factory;
    if (f == null || _error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(i18n.t('factory_page_heading'))),
        body: SFStateView(
          message: i18n.t(
            _error != null
                ? 'fc_load_failed'
                : widget.factoryId <= 0
                ? 'fx_no_id'
                : 'factory_not_found',
          ),
          icon: _error != null ? Icons.cloud_off : Icons.factory_outlined,
          retryLabel: _error == null ? i18n.t('fx_browse_all') : null,
          onRetry: _error != null
              ? _load
              : () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const FactoriesPage()),
                ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: SFColors.white,
            foregroundColor: SFColors.darkGreen,
            title: Text(
              i18n.t('factory_page_heading'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (f.isMine)
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: i18n.t('btn_update'),
                  onPressed: () async {
                    final changed = await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => FactoryEditPage(factory: f),
                      ),
                    );
                    if (changed == true) _load();
                  },
                ),
            ],
          ),
          if (f.cover.isNotEmpty)
            SliverToBoxAdapter(
              child: ColoredBox(
                color: SFColors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SizedBox(height: 116, child: _Cover(factory: f)),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: Container(
              color: SFColors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SFImage(
                        url: f.logo,
                        width: 56,
                        height: 56,
                        radius: 12,
                        placeholderIcon: Icons.factory_outlined,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          f.name.isEmpty ? i18n.t('factory_no_name') : f.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (f.isApproved)
                        Tooltip(
                          message: i18n.t('factory_verified'),
                          child: const Icon(
                            Icons.verified,
                            color: SFColors.midGreen,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    [
                      if (f.industry.isNotEmpty)
                        _industryLabel(context, f.industry),
                      if (f.city.isNotEmpty || f.regionId.isNotEmpty)
                        _locationLabel(context, f),
                      '${_products.length} ${i18n.t('sup_products_count')}',
                      if (_follows != null)
                        '${_follows!.followers} ${i18n.t('fx_followers')}',
                    ].join(' · '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: SFColors.muted2,
                      height: 1.6,
                    ),
                  ),
                  if (f.isMine && !f.isApproved) ...[
                    const SizedBox(height: 10),
                    SFStatusChip(
                      status: f.status,
                      label: i18n.t(
                        f.status == 'rejected' ? 'fs_rejected' : 'fs_pending',
                      ),
                    ),
                    if (f.rejectionReason.isNotEmpty) Text(f.rejectionReason),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: f.isMine || _followBusy ? null : _follow,
                        icon: Icon(
                          _follows?.isFollowing == true
                              ? Icons.check
                              : Icons.add,
                          size: 18,
                        ),
                        label: Text(
                          i18n.t(
                            _follows?.isFollowing == true && !f.isMine
                                ? 'fx_following'
                                : 'fx_follow',
                          ),
                        ),
                      ),
                      if (f.websiteUri != null)
                        OutlinedButton.icon(
                          onPressed: _visitWebsite,
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: Text(i18n.t('fx_visit_site')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeader(
              TabBar(
                controller: _tabs,
                labelColor: SFColors.darkGreen,
                unselectedLabelColor: SFColors.muted2,
                indicatorColor: SFColors.midGreen,
                indicatorWeight: 3,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
                tabs: [
                  Tab(text: i18n.t('nav_home')),
                  Tab(text: i18n.t('factory_posts_title')),
                  Tab(text: i18n.t('factory_about_label')),
                  Tab(text: i18n.t('factory_products_title')),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            // الرئيسية: النبذة والمنشورات معاً.
            _HomeTab(
              factory: f,
              posts: _posts,
              onShowAbout: () => _tabs.animateTo(2),
            ),
            _PostsTab(factory: f, posts: _posts),
            _AboutTab(factory: f),
            _ProductsTab(products: _products),
          ],
        ),
      ),
      bottomNavigationBar: f.isMine
          ? null
          : Container(
              decoration: const BoxDecoration(
                color: SFColors.white,
                border: Border(top: BorderSide(color: SFColors.border)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: ElevatedButton.icon(
                    onPressed: _contact,
                    icon: const Icon(Icons.chat_bubble_outline, size: 20),
                    label: Text(i18n.t('msg_contact_btn')),
                  ),
                ),
              ),
            ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.factory});
  final SFFactory factory;
  @override
  Widget build(BuildContext context) =>
      SFImage(url: factory.cover, radius: SFMetrics.radius);
}

class _TabBarHeader extends SliverPersistentHeaderDelegate {
  _TabBarHeader(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => 48;

  @override
  double get maxExtent => 48;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) {
    return Container(
      decoration: const BoxDecoration(
        color: SFColors.white,
        border: Border(bottom: BorderSide(color: SFColors.border)),
      ),
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarHeader old) => old.tabBar != tabBar;
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.factory,
    required this.posts,
    required this.onShowAbout,
  });

  final SFFactory factory;
  final List<SFPost> posts;
  final VoidCallback onShowAbout;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AboutCard(factory: factory),
        TextButton(
          onPressed: onShowAbout,
          child: Text(context.t('about_show_all')),
        ),
        const SizedBox(height: 14),
        ...posts.map(
          (p) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _PostCard(post: p, factory: factory),
          ),
        ),
        if (posts.isEmpty) SFStateView(message: context.t('factory_no_posts')),
      ],
    );
  }
}

class _PostsTab extends StatelessWidget {
  const _PostsTab({required this.posts, required this.factory});

  final List<SFPost> posts;
  final SFFactory factory;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return SFStateView(message: context.t('factory_no_posts'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _PostCard(post: posts[i], factory: factory),
    );
  }
}

class _AboutTab extends StatelessWidget {
  const _AboutTab({required this.factory});

  final SFFactory factory;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [_AboutCard(factory: factory, expanded: true)],
    );
  }
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({required this.products});
  final List<SFProduct> products;
  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return SFStateView(message: context.t('factory_no_products'));
    }
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          mainAxisExtent: (constraints.maxWidth - 44) / 2 / 1.18 + 118,
        ),
        itemCount: products.length,
        itemBuilder: (_, index) => CatalogProductCard(product: products[index]),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.factory, this.expanded = false});

  final SFFactory factory;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SFColors.white,
        border: Border.all(color: SFColors.border),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            i18n.t('factory_about_label'),
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            factory.about.isEmpty ? i18n.t('factory_no_about') : factory.about,
            maxLines: expanded ? null : 6,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.65),
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 10),
            if (factory.industry.isNotEmpty)
              _InfoRow(
                label: i18n.t('field_industry'),
                value: _industryLabel(context, factory.industry),
              ),
            if (factory.city.isNotEmpty)
              _InfoRow(
                label: i18n.t('addr_city'),
                value: _locationLabel(context, factory),
              ),
            if (factory.district.isNotEmpty)
              _InfoRow(label: i18n.t('addr_district'), value: factory.district),
            if (factory.companySize.isNotEmpty)
              _InfoRow(
                label: i18n.t('field_company_size'),
                value: factory.companySize,
              ),
            if (factory.website.isNotEmpty)
              _InfoRow(label: i18n.t('field_website'), value: factory.website),
          ],
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: SFColors.muted2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.factory});

  final SFPost post;
  final SFFactory factory;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SFColors.white,
        border: Border.all(color: SFColors.border),
        borderRadius: BorderRadius.circular(SFMetrics.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SFImage(
                url: factory.logo,
                width: 38,
                height: 38,
                radius: 19,
                placeholderIcon: Icons.factory_outlined,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      factory.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      DateFormat.yMMMd(context.i18n.dateLocale)
                          .format(post.createdAt),
                      style: const TextStyle(
                        fontSize: 11,
                        color: SFColors.muted2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (post.body.isNotEmpty)
            Text(post.body, style: const TextStyle(fontSize: 14, height: 1.65)),
          if (post.image.isNotEmpty) ...[
            const SizedBox(height: 10),
            SFImage(url: post.image, height: 180, fit: BoxFit.cover),
          ],
          if (post.video.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                try {
                  if (!await launchUrl(
                    Uri.parse(post.video),
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('تعذّر فتح المقطع');
                  }
                } catch (error) {
                  if (context.mounted) showSFError(context, error);
                }
              },
              icon: const Icon(Icons.play_circle_outline),
              label: Text(context.t('factory_watch_video')),
            ),
        ],
      ),
    );
  }
}

String _industryLabel(BuildContext context, String key) {
  for (final cat in context.i18n.categories) {
    if (context.i18n.categoryKey(cat) == key ||
        cat.values.any(
          (name) => name.toLowerCase() == key.trim().toLowerCase(),
        )) {
      return context.i18n.categoryName(cat);
    }
  }
  return key;
}

String _locationLabel(BuildContext context, SFFactory factory) {
  final city = factory.city.trim();
  if (city.isEmpty) return context.i18n.regionName(factory.regionId);
  for (final region in kRegionNames.entries) {
    if (region.key.toLowerCase() == city.toLowerCase() ||
        region.value.values.any(
          (name) => name.toLowerCase() == city.toLowerCase(),
        )) {
      return context.i18n.regionName(region.key);
    }
  }
  return city;
}
