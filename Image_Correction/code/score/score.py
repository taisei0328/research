import cv2
import numpy as np
import os
from PIL import Image

# 各クラスの色範囲設定（HSV色空間）
class_colors = {
    'door': [(np.array([0, 0, 100]), np.array([180, 20, 200]))],  # 灰色
    'wall': [(np.array([90, 0, 0]), np.array([255, 255, 255]))],  # 藤色
    'object': [(np.array([145, 50, 100]), np.array([165, 255, 255]))],  # タフィーピンク
    'eave': [(np.array([35, 100, 100]), np.array([85, 255, 255]))],  # ライトシーグリーン
    'roof': [(np.array([100, 150, 50]), np.array([140, 255, 255]))],  # 青
    'window': [(np.array([90, 50, 100]), np.array([110, 255, 255]))]  # 水色
}

def create_class_masks(segmentation_img):
    """セグメンテーション画像からクラスごとのマスクを生成"""
    hsv_img = cv2.cvtColor(segmentation_img, cv2.COLOR_BGR2HSV)
    masks = {}

    # すべてのクラスのマスクを生成
    for class_name, color_ranges in class_colors.items():
        mask = np.zeros(hsv_img.shape[:2], dtype=np.uint8)
        for low_color, high_color in color_ranges:
            temp_mask = cv2.inRange(hsv_img, low_color, high_color)
            mask = cv2.bitwise_or(mask, temp_mask)
        
        masks[class_name] = mask

    # wallのマスクを作成
    wall_mask = masks['wall']

    # wallのマスクを使って、他の部分を除外
    for other_class, other_mask in masks.items():
        if other_class != 'wall':
            wall_mask = cv2.bitwise_and(wall_mask, cv2.bitwise_not(other_mask))

    masks['wall'] = wall_mask  # 更新されたwallマスクを保存
    return masks

def resize_segmentation_image(image, size=(600, 400)):
    """セグメンテーション画像を指定サイズにリサイズ"""
    return cv2.resize(image, size, interpolation=cv2.INTER_LANCZOS4)

def resize_and_crop_heatmap(image_path, output_size, scale=1.5):
    """ヒートマップ画像をリサイズしてクロップ"""
    image = Image.open(image_path)
    width, height = image.size
    new_width = int(width * scale)
    new_height = int(height * scale)
    resized_image = image.resize((new_width, new_height), Image.LANCZOS)
    
    left = (new_width - output_size[0]) // 2
    top = (new_height - output_size[1]) // 2
    right = left + output_size[0]
    bottom = top + output_size[1]
    
    cropped_image = resized_image.crop((left, top, right, bottom))
    return np.array(cropped_image)

def apply_masks_and_calculate_means(segmentation_dir, heatmap_dir, output_dir, heatmap_size):
    os.makedirs(output_dir, exist_ok=True)

    segmentation_files = os.listdir(segmentation_dir)
    
    for segmentation_file in segmentation_files:
        segmentation_path = os.path.join(segmentation_dir, segmentation_file)
        segmentation_img = cv2.imread(segmentation_path)

        if segmentation_img is None:
            print(f"画像の読み込みエラー: {segmentation_path}")
            continue

        # セグメンテーション画像をリサイズ
        segmentation_img = resize_segmentation_image(segmentation_img)

        # ヒートマップ画像のパスを作成 (ファイル名が同じ)
        heatmap_path = os.path.join(heatmap_dir, segmentation_file)

        # ヒートマップをリサイズしてクロップ
        heatmap_img = resize_and_crop_heatmap(heatmap_path, heatmap_size)

        if heatmap_img is None:
            print(f"ヒートマップ画像の読み込みエラー: {heatmap_path}")
            continue

        # クラスマスクを作成
        masks = create_class_masks(segmentation_img)

        # 各クラスごとにマスクを適用し、明るさの平均を計算
        for class_name, mask in masks.items():
            masked_heatmap = cv2.bitwise_and(heatmap_img, heatmap_img, mask=mask)

            # マスクされた部分の平均値を計算
            mean_val = cv2.mean(masked_heatmap, mask=mask)[:3]  # BGR値
            mean_brightness = np.mean(mean_val)  # BGRの平均を計算

            # 平均値を出力
            print(f"{segmentation_file} の {class_name} の平均明るさ: {mean_brightness:.2f}")

            # マスク画像を保存
            masked_output_path = os.path.join(output_dir, f"{segmentation_file}_mask_{class_name}.png")
            cv2.imwrite(masked_output_path, masked_heatmap)
            print(f"{segmentation_file} の {class_name} のマスク画像を保存しました: {masked_output_path}")

if __name__ == '__main__':
    segmentation_dir = r"C:\Users\taisei\Desktop\Resize_Overray\segment"
    heatmap_dir = r"C:\Users\taisei\Desktop\Resize_Overray\heatmap"  # ヒートマップのフォルダパス
    output_dir = r"C:\Users\taisei\Desktop\Resize_Overray\output"
    heatmap_size = (600, 400)  # クロップ後のヒートマップのサイズ
    apply_masks_and_calculate_means(segmentation_dir, heatmap_dir, output_dir, heatmap_size)
