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

import '../core/i18n.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/factory_service.dart';
import '../services/messages_service.dart';
import '../widgets/common.dart';
import 'chat_page.dart';
import 'factory_edit_page.dart';
import 'product_page.dart';

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
      final p = await FactoryService.products(widget.factoryId);
      final posts = await FactoryService.posts(widget.factoryId);
      if (!mounted) return;
      setState(() {
        _factory = f;
        _products = p;
        _posts = posts;
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
          message: i18n.t('fc_load_failed'),
          icon: Icons.cloud_off,
          onRetry: _load,
        ),
      );
    }

    return Scaffold(
      backgroundColor: SFColors.pageBg,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            expandedHeight: 210,
            backgroundColor: SFColors.darkGreen,
            foregroundColor: SFColors.white,
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
            flexibleSpace: FlexibleSpaceBar(
              background: _Cover(factory: f),
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarHeader(
              TabBar(
                controller: _tabs,
                labelColor: SFColors.darkGreen,
                unselectedLabelColor: SFColors.muted2,
                indicatorColor: SFColors.green,
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
            _HomeTab(factory: f, posts: _posts),
            _PostsTab(posts: _posts),
            _AboutTab(factory: f),
            _ProductsTab(products: _products),
          ],
        ),
      ),
      bottomNavigationBar: f.isMine
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ElevatedButton.icon(
                  onPressed: _contact,
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: Text(i18n.t('msg_contact_btn')),
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
  Widget build(BuildContext context) {
    final i18n = context.i18n;

    return Stack(
      fit: StackFit.expand,
      children: [
        // الغلاف بارتفاع ثابت لا بنسبة أبعاد — النسبة تكبر مع
        // عرض الحاوية وكانت تُنتج غلافاً ضخماً.
        if (factory.cover.isNotEmpty)
          Image.network(
            factory.cover,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                Container(color: SFColors.midGreen),
          )
        else
          Container(color: SFColors.midGreen),
        // تدرّج يضمن قراءة النص فوق أي صورة.
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0xCC04361B)],
            ),
          ),
        ),
        Positioned(
          bottom: 14,
          right: 16,
          left: 16,
          child: Row(
            children: [
              SFImage(
                url: factory.logo,
                width: 58,
                height: 58,
                radius: 10,
                placeholderIcon: Icons.factory_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      factory.name.isEmpty ? '—' : factory.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SFColors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (factory.industry.isNotEmpty)
                      Text(
                        factory.industry,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SFColors.muted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              if (factory.isMine && !factory.isApproved)
                SFStatusChip(
                  status: factory.status,
                  label: i18n.t(switch (factory.status) {
                    'approved' => 'fs_approved',
                    'rejected' => 'fs_rejected',
                    _ => 'fs_pending',
                  }),
                ),
            ],
          ),
        ),
      ],
    );
  }
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
    return Container(color: SFColors.white, child: tabBar);
  }

  @override
  bool shouldRebuild(_TabBarHeader old) => old.tabBar != tabBar;
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({required this.factory, required this.posts});

  final SFFactory factory;
  final List<SFPost> posts;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _AboutCard(factory: factory),
        const SizedBox(height: 14),
        ...posts.map((p) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _PostCard(post: p),
            )),
      ],
    );
  }
}

class _PostsTab extends StatelessWidget {
  const _PostsTab({required this.posts});

  final List<SFPost> posts;

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return SFStateView(message: context.t('factory_no_posts'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: posts.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _PostCard(post: posts[i]),
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
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemCount: products.length,
      itemBuilder: (context, i) {
        final p = products[i];
        return InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ProductPage(product: p)),
          ),
          borderRadius: BorderRadius.circular(SFMetrics.radius),
          child: Container(
            decoration: BoxDecoration(
              color: SFColors.white,
              border: Border.all(color: SFColors.border),
              borderRadius: BorderRadius.circular(SFMetrics.radius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: SFImage(url: p.image)),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (p.price > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${p.price.toStringAsFixed(2)} ر.س',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: SFColors.midGreen,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
            factory.about.isEmpty ? '—' : factory.about,
            maxLines: expanded ? null : 6,
            overflow: expanded ? null : TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.8),
          ),
          if (expanded) ...[
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            if (factory.industry.isNotEmpty)
              _InfoRow(label: i18n.t('field_industry'), value: factory.industry),
            if (factory.city.isNotEmpty)
              _InfoRow(label: i18n.t('addr_city'), value: factory.city),
            if (factory.district.isNotEmpty)
              _InfoRow(
                  label: i18n.t('addr_district'), value: factory.district),
            if (factory.companySize.isNotEmpty)
              _InfoRow(
                  label: i18n.t('field_company_size'),
                  value: factory.companySize),
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
            width: 120,
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
  const _PostCard({required this.post});

  final SFPost post;

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
          if (post.body.isNotEmpty)
            Text(
              post.body,
              style: const TextStyle(fontSize: 14, height: 1.8),
            ),
          if (post.image.isNotEmpty) ...[
            const SizedBox(height: 10),
            SFImage(url: post.image, height: 180, fit: BoxFit.cover),
          ],
        ],
      ),
    );
  }
}
