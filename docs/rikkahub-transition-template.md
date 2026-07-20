# RikkaHub 页面跳转动画复刻模板

这份文档用于两类场景：

1. 快速定位一个 Android 项目的页面跳转动画实现。
2. 在 Flutter 项目中复刻 RikkaHub 当前使用的页面切换动画和 Hero 共享元素动画。

适用对象：

- 人工排查现有 Android 项目。
- 让智能体在 Flutter 项目里快速添加同款动画。

## 1. 原项目动画结论

RikkaHub 的页面跳转动画由两层组成，不是单一效果：

1. 全局路由切换动画。
2. 局部共享元素 Hero 动画。

### 1.1 全局路由切换动画

来源文件：

- `app/src/main/java/me/rerere/rikkahub/RouteActivity.kt`

核心实现位置：

- `NavDisplay.transitionSpec`
- `NavDisplay.popTransitionSpec`
- `NavDisplay.predictivePopTransitionSpec`

行为总结：

- 前进 `push`
  - 新页面从右侧完整滑入。
  - 旧页面向左移动半屏。
  - 旧页面同时缩小到 `0.7`。
  - 旧页面同时淡出。
- 返回 `pop`
  - 上一个页面从左侧半屏位置滑回。
  - 上一个页面从 `0.7` 放大回 `1.0`。
  - 上一个页面淡入。
  - 当前页面向右完整滑出。

对应源码片段：

```kotlin
transitionSpec = {
    if (backStack.size == 1) fadeIn() togetherWith fadeOut()
    else {
        slideInHorizontally { it } togetherWith
            slideOutHorizontally { -it / 2 } + scaleOut(targetScale = 0.7f) + fadeOut()
    }
}

popTransitionSpec = {
    slideInHorizontally { -it / 2 } + scaleIn(initialScale = 0.7f) + fadeIn() togetherWith
        slideOutHorizontally { it }
}
```

备注：

- `ChatPage` 被单独覆盖成纯淡入淡出，不走这套滑动缩放逻辑。

### 1.2 Hero 共享元素动画

来源文件：

- `app/src/main/java/me/rerere/rikkahub/ui/hooks/HeroAnimation.kt`
- `app/src/main/java/me/rerere/rikkahub/RouteActivity.kt`

行为总结：

- 整个应用被 `SharedTransitionLayout` 包裹。
- 头像通过同一个 key 做 `sharedElement` 过渡。
- 同一个助手在不同页面的头像尺寸不同，但会平滑变形过渡。

对应源码片段：

```kotlin
fun Modifier.heroAnimation(
    key: Any,
): Modifier {
    val sharedTransitionScope = LocalSharedTransitionScope.current
    val animatedVisibilityScope = LocalNavAnimatedContentScope.current
    return with(sharedTransitionScope) {
        this@heroAnimation.sharedElement(
            sharedContentState = rememberSharedContentState(key),
            animatedVisibilityScope = animatedVisibilityScope
        )
    }
}
```

已确认的调用位置：

- 助手列表页头像
- 助手详情页头像
- 助手基础设置页头像

共享 key 形式：

```text
assistant_<assistant.id>
```

## 2. 快速定位 Android 页面动画的排查模板

当你要看别人的 Android 项目时，不要先逐页读业务代码，先按下面顺序缩小搜索范围。

### 2.1 第一步：先判断技术栈

优先看：

- `build.gradle`
- `build.gradle.kts`
- 根导航 Activity
- 入口页面的 import

目标是先回答下面的问题：

- 是传统 `Activity`/`Fragment` 方案，还是 Jetpack Compose？
- 是 XML 动画，还是代码里直接定义过渡？
- 用的是 `Navigation Compose`、`Navigation 3`、`FragmentTransaction` 还是自定义路由？

### 2.2 第二步：搜高信号关键词

传统 Android / Fragment 常用关键词：

```text
overridePendingTransition
setCustomAnimations
FragmentTransaction
ActivityOptions
sharedElement
windowAnimationStyle
res/anim
res/animator
```

Jetpack Compose 常用关键词：

```text
NavHost
NavDisplay
AnimatedContent
transitionSpec
enterTransition
exitTransition
popEnterTransition
popExitTransition
SharedTransitionLayout
sharedElement
MaterialContainerTransform
Hero
```

### 2.3 第三步：先找定义处，再找调用处

正确顺序：

1. 先找动画定义在哪里。
2. 再找它被哪些页面或组件调用。

原因：

- 定义处决定动画本体。
- 调用处决定动画发生在哪些页面之间。

### 2.4 第四步：分清是两层还是一层

很多项目的“页面切换动画”实际是两层叠加：

1. 整页进出场动画。
2. 某个局部元素的共享元素动画。

如果只看其中一层，容易误判。

### 2.5 给智能体的排查指令模板

可以直接把下面这段交给智能体：

```text
请帮我快速定位这个 Android 项目的页面跳转动画实现，不要先逐页读业务代码。

按下面顺序排查：
1. 先判断项目是 Activity/Fragment、Jetpack Compose，还是其他导航方案。
2. 优先搜索这些关键词：overridePendingTransition、setCustomAnimations、FragmentTransaction、NavHost、NavDisplay、AnimatedContent、transitionSpec、SharedTransitionLayout、sharedElement。
3. 先告诉我动画定义在哪些文件和函数里，再告诉我哪些页面在调用这些动画。
4. 把结果拆成“全局页面切换动画”和“局部共享元素动画”两部分总结。
5. 如果能复刻到 Flutter，请顺手给出 Flutter 对应实现方案。
```

## 3. Flutter 复刻方案

Flutter 里推荐按同样的两层实现：

1. 全局路由过渡动画。
2. 头像 Hero 动画。

## 3.1 动画效果对照

RikkaHub Android 原始效果到 Flutter 的映射关系如下：

| Android 效果 | Flutter 对应 |
| --- | --- |
| 新页面从右侧滑入 | `SlideTransition` |
| 旧页面向左滑出半屏 | `secondaryAnimation` + `SlideTransition` |
| 旧页面缩小到 `0.7` | `ScaleTransition` |
| 旧页面淡出 | `FadeTransition` |
| 头像共享元素变形 | `Hero` |

## 3.2 Flutter 全局路由动画代码

下面这份代码适合直接放进 Flutter 项目中作为全局页面切换动画。

```dart
import 'package:flutter/material.dart';

class RikkaPageTransitionsBuilder extends PageTransitionsBuilder {
  const RikkaPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );

    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curve),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.5, 0),
        ).animate(secondaryCurve),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 1,
            end: 0.7,
          ).animate(secondaryCurve),
          child: FadeTransition(
            opacity: Tween<double>(
              begin: 1,
              end: 0,
            ).animate(secondaryCurve),
            child: child,
          ),
        ),
      ),
    );
  }
}
```

这份实现的效果是：

- push 时，新页面从右侧进入。
- push 时，下层旧页面左移半屏、缩小到 `0.7`、淡出。
- pop 时，下层页面自动反向恢复。

如果你想在局部页面上单独使用同款过渡，也可以封装一个 `PageRouteBuilder`：

```dart
import 'package:flutter/material.dart';

class RikkaRoute<T> extends PageRouteBuilder<T> {
  RikkaRoute({
    required Widget page,
    RouteSettings? settings,
  }) : super(
          settings: settings,
          transitionDuration: const Duration(milliseconds: 320),
          reverseTransitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curve = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeOutCubic,
            );

            final secondaryCurve = CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeOutCubic,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(curve),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset.zero,
                  end: const Offset(-0.5, 0),
                ).animate(secondaryCurve),
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: 1,
                    end: 0.7,
                  ).animate(secondaryCurve),
                  child: FadeTransition(
                    opacity: Tween<double>(
                      begin: 1,
                      end: 0,
                    ).animate(secondaryCurve),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}
```

说明：

- `PageTransitionsBuilder` 更适合全局挂载。
- `PageRouteBuilder` 更适合单独页面使用。
- 大多数业务项目里，用 `PageTransitionsTheme + Hero` 已经足够接近原项目观感。

## 3.3 Flutter 全局接入方式

### MaterialApp 方式

```dart
MaterialApp(
  theme: ThemeData(
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: RikkaPageTransitionsBuilder(),
        TargetPlatform.iOS: RikkaPageTransitionsBuilder(),
      },
    ),
  ),
  home: const HomePage(),
);
```

### Navigator.push 方式

```dart
Navigator.of(context).push(
  RikkaRoute(
    page: const AssistantDetailPage(),
    settings: const RouteSettings(name: 'assistant_detail'),
  ),
);
```

### go_router 方式

```dart
CustomTransitionPage<void>(
  key: state.pageKey,
  child: const AssistantDetailPage(),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final curve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );

    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curve),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: const Offset(-0.5, 0),
        ).animate(secondaryCurve),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 1,
            end: 0.7,
          ).animate(secondaryCurve),
          child: FadeTransition(
            opacity: Tween<double>(
              begin: 1,
              end: 0,
            ).animate(secondaryCurve),
            child: child,
          ),
        ),
      ),
    );
  },
)
```

## 3.4 Flutter Hero 头像代码

三处页面都使用同一个 `tag`：

```dart
Hero(
  tag: 'assistant_$assistantId',
  transitionOnUserGestures: true,
  child: CircleAvatar(
    radius: 24,
    backgroundImage: imageProvider,
  ),
)
```

不同页面可以用不同尺寸：

- 列表页：`radius: 24`
- 详情页：`radius: 50`
- 基础设置页：`radius: 40`

示例：

```dart
class AssistantAvatar extends StatelessWidget {
  const AssistantAvatar({
    super.key,
    required this.assistantId,
    required this.radius,
    this.imageProvider,
  });

  final String assistantId;
  final double radius;
  final ImageProvider? imageProvider;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: 'assistant_$assistantId',
      transitionOnUserGestures: true,
      child: CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
      ),
    );
  }
}
```

## 3.5 Flutter 页面结构建议

如果你要让智能体自动添加这套动画，建议它按下面结构落地：

```text
lib/
  navigation/
    rikka_page_transitions.dart
    rikka_route.dart
  widgets/
    assistant_avatar.dart
```

推荐职责：

- `rikka_page_transitions.dart`
  - 放全局路由过渡。
- `rikka_route.dart`
  - 放按页面单独 push 的过渡封装。
- `assistant_avatar.dart`
  - 放 Hero 头像组件。

## 4. 给智能体直接使用的 Flutter 实现提示词

如果你想让智能体直接在一个 Flutter 项目里落地这套动画，可以把下面这段直接发给它。

```text
请在当前 Flutter 项目中复刻 RikkaHub 的页面跳转动画，并直接修改代码。

目标效果：
1. 页面 push 时，新页面从右向左滑入。
2. 页面切换时，旧页面向左移动半屏，并带轻微缩小和淡出。
3. 页面 pop 时，上一页从左侧半屏位置滑回，同时恢复缩放并淡入。
4. 列表页头像 -> 详情页头像 -> 编辑页头像，使用同一个 Hero tag 做共享元素过渡。

实现要求：
1. 优先复用当前项目已有的导航方案，不要强行重构。
2. 如果项目使用 MaterialApp，请优先通过 pageTransitionsTheme 注入全局动画。
3. 如果项目使用 go_router，请在 CustomTransitionPage 中实现同等过渡。
4. 新增一个可复用头像组件，统一 Hero tag 规则为 assistant_<id>。
5. 改动完成后告诉我：
   - 修改了哪些文件
   - 如何在新页面继续复用这套动画
   - 哪些效果与 Android Compose 原版完全一致，哪些是 Flutter 下的近似实现
```

## 5. 给智能体直接使用的“先分析后复刻”提示词

如果你面对的是一个陌生项目，建议先让智能体分析，再复刻：

```text
请先分析当前项目的导航实现和页面切换动画，再决定如何复刻 RikkaHub 动画。

执行顺序：
1. 先确认项目使用 Navigator 1.0、Navigator 2.0、go_router、auto_route 还是其他方案。
2. 找出当前项目已有的全局页面过渡实现位置。
3. 在不破坏现有导航结构的前提下，添加一套接近 RikkaHub 的页面过渡：
   - push: 新页右侧滑入
   - 下层页左移半屏、缩小到 0.7、淡出
   - pop: 反向恢复
4. 为头像或卡片头图添加 Hero 共享元素支持。
5. 优先做最小侵入式改造，避免全量重构导航。
6. 改完后输出修改说明和复用方式。
```

## 6. 落地建议

如果只是追求视觉接近，推荐优先使用下面组合：

1. `PageTransitionsTheme`
2. `Hero`
3. 统一的页面 push 封装

这样成本低、适配面广，也最适合交给智能体自动化添加。

如果追求和 Android Compose 原实现更接近，则需要额外处理：

1. 下层页面的缩放和淡出。
2. pop 手势过程中的联动动画。
3. 局部共享元素在复杂布局中的裁剪和 z-order 问题。

## 7. 本文档引用的 RikkaHub 源码位置

- `app/src/main/java/me/rerere/rikkahub/RouteActivity.kt`
- `app/src/main/java/me/rerere/rikkahub/ui/hooks/HeroAnimation.kt`
- `app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/AssistantPage.kt`
- `app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/detail/AssistantDetailPage.kt`
- `app/src/main/java/me/rerere/rikkahub/ui/pages/assistant/detail/AssistantBasicPage.kt`
