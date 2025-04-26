import cv2
import numpy as np
import os
from PIL import Image

# 各クラスの色範囲設定（HSV色空間）
class_colors = {
    'door': [(np.array([0, 0, 100]), np.array([180, 20, 200]))],  # 灰色
    'wall': [(np.array([90, 0, 0]), np.array([255, 255, 255]))],
    'object': [(np.array([145, 50, 100]), np.array([165, 255, 255]))],  # タフィーピンク
    'eave': [(np.array([35, 100, 100]), np.array([85, 255, 255]))],  # ライトグリーン
    'roof': [(np.array([110, 150, 90]), np.array([220, 255, 255]))],  # 青
    'window': [(np.array([90, 50, 100]), np.array([110, 255, 255]))]  # ライトブルー
}

def resize_and_crop_heatmap(image_path, output_size, scale=1.5, offset_x=-35):
    image = Image.open(image_path)
    width, height = image.size
    new_width = int(width * scale)
    new_height = int(height * scale)
    new_size = (new_width, new_height)
    resized_image = image.resize(new_size, Image.LANCZOS)
    
    left = (new_width - output_size[0]) // 2 + offset_x  # オフセットを追加
    top = (new_height - output_size[1]) // 2
    right = left + output_size[0]
    bottom = top + output_size[1]
    
    # クロップの範囲が画像の範囲を超えないように調整
    left = max(left, 0)
    right = min(right, new_width)
    top = max(top, 0)
    bottom = min(bottom, new_height)
    
    cropped_image = resized_image.crop((left, top, right, bottom))
    return np.array(cropped_image)

def calculate_brightness(segmentation_img, heatmap_img, masks):
    brightness_scores = {}
    
    for class_name, mask in masks.items():
        masked_heatmap = cv2.bitwise_and(heatmap_img, heatmap_img, mask=mask)
        # 明るさの指標を計算（単純合計）
        brightness = cv2.sumElems(masked_heatmap)[0] + cv2.sumElems(masked_heatmap)[1] + cv2.sumElems(masked_heatmap)[2]  # B + G + Rの合計
        pixel_count = cv2.countNonZero(mask)  # 非0のピクセルを数える
        
        if pixel_count > 0:
            average_brightness = brightness / pixel_count
            brightness_scores[class_name] = average_brightness
        else:
            brightness_scores[class_name] = 0

    return brightness_scores

def extract_all_classes_from_folder(segmentation_dir, heatmap_dir, output_dir):
    os.makedirs(output_dir, exist_ok=True)

    # マスク画像とヒートマップ画像用のフォルダを作成
    mask_output_dir = os.path.join(output_dir, "mask_images")
    heatmap_output_dir = os.path.join(output_dir, "masked_heatmap_images")
    os.makedirs(mask_output_dir, exist_ok=True)
    os.makedirs(heatmap_output_dir, exist_ok=True)

    for class_name in class_colors.keys():
        class_mask_dir = os.path.join(mask_output_dir, class_name)
        class_heatmap_dir = os.path.join(heatmap_output_dir, class_name)
        os.makedirs(class_mask_dir, exist_ok=True)
        os.makedirs(class_heatmap_dir, exist_ok=True)

    for segmentation_file in os.listdir(segmentation_dir):
        segmentation_path = os.path.join(segmentation_dir, segmentation_file)
        segmentation_img = cv2.imread(segmentation_path)

        if segmentation_img is None:
            print(f"画像の読み込みエラー: {segmentation_path}")
            continue
        
        # セグメンテーション画像を600x400にリサイズ
        segmentation_img = cv2.resize(segmentation_img, (600, 400))

        # ヒートマップ画像を取得してリサイズ・クロップ
        heatmap_path = os.path.join(heatmap_dir, segmentation_file)
        heatmap_img = resize_and_crop_heatmap(heatmap_path, output_size=(600, 400))
        
        # BGRからHSVに変換
        hsv_img = cv2.cvtColor(segmentation_img, cv2.COLOR_BGR2HSV)

        # マスクを生成
        masks = {}
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

        # 背景を無視して、wallの領域だけを表示
        extracted_wall_area = cv2.bitwise_and(segmentation_img, segmentation_img, mask=wall_mask)

        # 壁のヒートマップを純正な壁のマスクで保存
        pure_wall_heatmap = cv2.bitwise_and(heatmap_img, heatmap_img, mask=wall_mask)

        # 壁のヒートマップに対して明るさを計算
        brightness_wall = cv2.sumElems(pure_wall_heatmap)[0]+cv2.sumElems(pure_wall_heatmap)[1]+cv2.sumElems(pure_wall_heatmap)[2]
        pixel_count_wall = cv2.countNonZero(wall_mask)  # 非0のピクセルを数える
        if pixel_count_wall > 0:
            average_wall_brightness = brightness_wall / pixel_count_wall
        else:
            average_wall_brightness = 0

        # 明るさを計算（全クラス、壁を除外）
        masks_without_wall = {class_name: mask for class_name, mask in masks.items() if class_name != 'wall'}
        brightness_scores = calculate_brightness(segmentation_img, heatmap_img, masks_without_wall)

        # 結果を表示（壁の明るさも含めて）
        print(f"{segmentation_file} の wall の平均明るさ: {average_wall_brightness:.2f}")
        for class_name, score in brightness_scores.items():
            print(f"{segmentation_file} の {class_name} の平均明るさ: {score:.2f}")

        # 壁のヒートマップを保存
        pure_wall_mask_output_path = os.path.join(heatmap_output_dir, "wall", f"{segmentation_file}_masked_heatmap_wall.png")
        cv2.imwrite(pure_wall_mask_output_path, pure_wall_heatmap)

        # 壁のマスク画像を保存
        wall_mask_output_path = os.path.join(mask_output_dir, "wall", f"{segmentation_file}_wall_mask_true.png")
        cv2.imwrite(wall_mask_output_path, wall_mask)

        # 各クラスのヒートマップをマスクした画像とマスク画像を保存
        for class_name, mask in masks.items():
            masked_heatmap = cv2.bitwise_and(heatmap_img, heatmap_img, mask=mask)
            
            # ヒートマップを保存
            masked_heatmap_output_path = os.path.join(heatmap_output_dir, class_name, f"{segmentation_file}_masked_heatmap_{class_name}.png")
            cv2.imwrite(masked_heatmap_output_path, masked_heatmap)

            # マスク画像を保存
            mask_output_path = os.path.join(mask_output_dir, class_name, f"{segmentation_file}_mask_{class_name}.png")
            cv2.imwrite(mask_output_path, mask)

if __name__ == '__main__':
    segmentation_dir = r"C:\Users\taisei\Desktop\analaysis_dataset\segment"
    heatmap_dir = r"C:\Users\taisei\Desktop\analaysis_dataset\heatmap"
    output_dir = r"C:\Users\taisei\Desktop\analaysis_dataset\output_4"
    extract_all_classes_from_folder(segmentation_dir, heatmap_dir, output_dir)









