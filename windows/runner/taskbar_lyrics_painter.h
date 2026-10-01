#ifndef RUNNER_TASKBAR_LYRICS_PAINTER_H_
#define RUNNER_TASKBAR_LYRICS_PAINTER_H_

#include <map>
#include <memory>
#include <string>
#include <tuple>

#include "gdiplus_include.h"

// 任务栏歌词的 GDI+ 绘制（只在任务栏窗口线程使用）。
//
// 两种画面：
// - 歌词：三行「胶片」（上一句 / 当前句 / 下一句）整体上滚切换；当前句大而亮，下一句小而暗；
//   长句先缩小（最低 72%），仍放不下就均分折成两行铺满高度（此时不做上滚）；
// - 控制条：封面 + 歌名 / 歌手 + 上一首 / 播放暂停 / 下一首（没有同步歌词或鼠标悬停时）。
// 字体优先用 App 自带的 MiSans，韩文 / 泰文等 MiSans 没有的文字换系统字体。
class TaskbarLyricsPainter {
 public:
  struct Canvas {
    Gdiplus::Graphics* graphics;
    int width;
    int height;
    double scale;          // 任务栏 DPI / 96
    Gdiplus::Color color;  // 文字颜色（不含整体不透明度）
    int opacity;           // 15 ~ 100
  };

  // 控制条各区域（客户区坐标），用于命中测试。
  struct ControlLayout {
    Gdiplus::Rect info;  // 封面 + 文字：点按打开 Flutify
    Gdiplus::Rect previous;
    Gdiplus::Rect play;
    Gdiplus::Rect next;
  };

  enum class Button { kNone, kPrevious, kPlay, kNext };

  TaskbarLyricsPainter();
  ~TaskbarLyricsPainter();

  TaskbarLyricsPainter(const TaskbarLyricsPainter&) = delete;
  TaskbarLyricsPainter& operator=(const TaskbarLyricsPainter&) = delete;

  // 当前句是否需要折成两行。
  bool NeedsWrap(const Canvas& canvas, const std::wstring& current);

  // [progress]：切句动画进度（0 = 刚切换，1 = 静止），已做缓动。
  void PaintLyrics(const Canvas& canvas, const std::wstring& previous, const std::wstring& current,
                   const std::wstring& next, float progress);

  ControlLayout PaintControl(const Canvas& canvas, const std::wstring& title, const std::wstring& artist,
                             Gdiplus::Bitmap* art, bool playing, Button hovered);

 private:
  Gdiplus::Font* FontFor(const std::wstring& text, double points, bool bold);
  const Gdiplus::FontFamily* FamilyFor(const std::wstring& text, bool bold);
  const Gdiplus::FontFamily* SystemFamily(const wchar_t* name);
  float MeasureWidth(Gdiplus::Graphics* g, const std::wstring& text, Gdiplus::Font* font);
  void DrawText(const Canvas& canvas, const std::wstring& text, Gdiplus::Font* font, const Gdiplus::RectF& rect,
                int alpha);
  void DrawFilmLine(const Canvas& canvas, const std::wstring& text, float top, float slot, double big_pt,
                    double small_pt, double width_scale);
  void DrawButton(const Canvas& canvas, Button kind, const Gdiplus::Rect& rect, bool playing, bool hovered);

  // App 自带的 MiSans（Demibold 作粗体、Regular 作常规）；加载失败时为空，退回系统字体
  std::unique_ptr<Gdiplus::PrivateFontCollection> bold_collection_;
  std::unique_ptr<Gdiplus::PrivateFontCollection> regular_collection_;
  std::unique_ptr<Gdiplus::FontFamily> bold_family_;
  std::unique_ptr<Gdiplus::FontFamily> regular_family_;
  std::map<std::wstring, std::unique_ptr<Gdiplus::FontFamily>> system_families_;

  // 字体对象与测宽结果缓存：动画期间每帧都要画同几句歌词
  std::map<std::tuple<const Gdiplus::FontFamily*, int, bool>, std::unique_ptr<Gdiplus::Font>> fonts_;
  std::map<std::wstring, float> widths_;

  std::unique_ptr<Gdiplus::StringFormat> text_format_;
};

#endif  // RUNNER_TASKBAR_LYRICS_PAINTER_H_
