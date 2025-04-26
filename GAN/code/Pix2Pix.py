#!/usr/bin/env python
# coding: utf-8

# In[ ]:





# In[1]:


import tensorflow as tf

# GPUの設定
physical_devices = tf.config.list_physical_devices('GPU')
if physical_devices:
    try:
        # メモリの動的割り当てを有効化
        for device in physical_devices:
            tf.config.experimental.set_memory_growth(device, True)
    except RuntimeError as e:
        # エラーが発生した場合は、設定がすでに初期化されていることを示す
        print(f"Error occurred: {e}")

# その他の処理
# 例: モデルの定義など


# In[2]:


# 必要なライブラリをインポート
import tensorflow as tf
from tensorflow.python.keras import layers
from tensorflow.python.keras.models import Sequential
import numpy as np
import matplotlib.pyplot as plt


# In[3]:


physical_devices = tf.config.experimental.list_physical_devices('GPU')
logical_devices = tf.config.experimental.list_logical_devices('GPU')

print(f"Physical devices: {physical_devices}")
print(f"Logical devices: {logical_devices}")


# In[4]:


import os
import numpy as np
import matplotlib.pyplot as plt
import tensorflow as tf
from tensorflow.keras import layers, models
from tensorflow.keras.preprocessing import image
from tensorflow.keras.applications import VGG19
from tqdm import tqdm
from sklearn.model_selection import train_test_split

# EarlyStoppingクラスを定義
class EarlyStopping:
    def __init__(self, patience=50, delta=0.001):
        self.patience = patience  # 改善が見られなくなったエポック数
        self.delta = delta  # 改善とみなす最小の変化量
        self.best_loss = np.inf  # 最良の損失値
        self.wait = 0  # 改善がないエポック数
        self.stopped_epoch = 0  # 訓練を停止したエポック数

    def check(self, val_loss):
        # 検証損失が改善されていない場合
        if val_loss < self.best_loss - self.delta:
            self.best_loss = val_loss
            self.wait = 0  # 改善があればリセット
        else:
            self.wait += 1
            if self.wait >= self.patience:
                self.stopped_epoch = epoch
                return True  # 訓練を停止する
        return False

# 画像を読み込む関数を定義
def load_image(img_path, target_size=(256, 256)):
    img = image.load_img(img_path, target_size=target_size)
    img_array = image.img_to_array(img)
    img_array = (img_array / 127.5) - 1.0  # [-1, 1] に正規化
    return img_array

# 訓練データと検証データを読み込む関数
def load_images_from_filenames(filenames, folder, batch_size=64):
    for i in tqdm(range(0, len(filenames), batch_size), desc="Loading images", unit="batch",disable = "True"):
        batch_filenames = filenames[i:i + batch_size]
        batch_images = []
        for filename in batch_filenames:
            if filename.endswith('.jpg') or filename.endswith('.png'):
                img = load_image(os.path.join(folder, filename))
                batch_images.append(img)
        yield np.array(batch_images)

# VGG19モデルの選択された層を使用してPerceptual Lossを計算
def get_vgg19_model():
    vgg = VGG19(weights='imagenet', include_top=False, input_shape=(256, 256, 3))
    selected_layers = [vgg.layers[i].output for i in [5, 9, 13]]  # 適切な層を選択
    return models.Model(inputs=vgg.input, outputs=selected_layers)

vgg_model = get_vgg19_model()
vgg_model.trainable = False

# Perceptual Lossの計算
def perceptual_loss(y_true, y_pred):
    feature_true = vgg_model(y_true)
    feature_pred = vgg_model(y_pred)
    loss = 0
    for ft, fp in zip(feature_true, feature_pred):
        loss += tf.reduce_mean(tf.abs(ft - fp))
    return loss

# L1 Loss
def l1_loss(y_true, y_pred):
    return tf.reduce_mean(tf.abs(y_true - y_pred))

# 交差エントロピー損失
def bce_loss(y_true, y_pred, smoothing=0.1):
    y_true = y_true * (1 - smoothing) + 0.5 * smoothing
    return tf.reduce_mean(tf.keras.losses.BinaryCrossentropy(from_logits=True)(y_true, y_pred))


# Residual Blockの定義
def residual_block(x, filters, kernel_size=3):
    skip = x
    x = layers.Conv2D(filters, kernel_size, padding="same")(x)
    x = layers.BatchNormalization()(x)
    x = layers.ReLU()(x)
    x = layers.Conv2D(filters, kernel_size, padding="same")(x)
    x = layers.BatchNormalization()(x)
    return layers.Add()([x, skip])


def build_generator_unet_with_residual():
    inputs = layers.Input(shape=[256, 256, 3])

    # Down-sampling layers
    down1 = layers.Conv2D(64, 4, strides=2, padding="same")(inputs)
    down1 = layers.LeakyReLU(alpha=0.2)(down1)

    down2 = layers.Conv2D(128, 4, strides=2, padding="same")(down1)
    down2 = layers.BatchNormalization()(down2)
    down2 = layers.LeakyReLU(alpha=0.2)(down2)

    # Residual Blocks at bottleneck
    bottleneck = layers.Conv2D(256, 4, strides=2, padding="same")(down2)
    bottleneck = layers.BatchNormalization()(bottleneck)
    bottleneck = layers.LeakyReLU(alpha=0.2)(bottleneck)
    bottleneck = residual_block(bottleneck, 256)
    bottleneck = residual_block(bottleneck, 256)

    # Up-sampling layers
    up1 = layers.Conv2DTranspose(128, 4, strides=2, padding="same")(bottleneck)
    up1 = layers.BatchNormalization()(up1)
    up1 = layers.ReLU()(up1)
    up1 = layers.Concatenate()([up1, down2])  # Skip connection

    up2 = layers.Conv2DTranspose(64, 4, strides=2, padding="same")(up1)
    up2 = layers.BatchNormalization()(up2)
    up2 = layers.ReLU()(up2)
    up2 = layers.Concatenate()([up2, down1])  # Skip connection

    # Output layer
    outputs = layers.Conv2D(3, 4, strides=1, padding="same", activation="tanh")(up2)

    return models.Model(inputs, outputs)


# 判別器の定義
def build_discriminator():
    inputs = layers.Input(shape=[256, 256, 3])
    targets = layers.Input(shape=[256, 256, 3])
    
    x = layers.Concatenate()([inputs, targets])
    x = layers.Conv2D(64, 4, strides=2, padding="same")(x)
    x = layers.LeakyReLU(alpha=0.2)(x)
    
    x = layers.Conv2D(128, 4, strides=2, padding="same")(x)
    x = layers.LeakyReLU(alpha=0.2)(x)
    
    x = layers.Conv2D(256, 4, strides=2, padding="same")(x)
    x = layers.LeakyReLU(alpha=0.2)(x)
    
    x = layers.Conv2D(512, 4, strides=2, padding="same")(x)
    x = layers.LeakyReLU(alpha=0.2)(x)
    
    x = layers.Conv2D(1, 4, strides=1, padding="same")(x)
    outputs = layers.Activation('sigmoid')(x)
    
    return models.Model([inputs, targets], outputs)



# 最適化
generator_optimizer = tf.keras.optimizers.Adam(learning_rate=3e-4, beta_1=0.5)
discriminator_optimizer = tf.keras.optimizers.Adam(learning_rate=1e-5, beta_1=0.5)

# 訓練ステップ
@tf.function
def train_step(real_x, real_y): 
    with tf.GradientTape() as gen_tape, tf.GradientTape() as disc_tape:
        fake_y = generator(real_x, training=True)
        fake_y_resized = tf.image.resize(fake_y, (256, 256))

        real_output = discriminator([real_x, real_y], training=True)
        fake_output = discriminator([real_x, fake_y_resized], training=True)

        # 個別損失の計算
        l1_loss_value = l1_loss(real_y, fake_y_resized)
        perceptual_loss_value = perceptual_loss(real_y, fake_y_resized)
        bce_loss_value_gen = bce_loss(tf.ones_like(fake_output), fake_output, smoothing=0.1)

        # Generatorの合計損失
        lambda_l1, lambda_perceptual, lambda_bce = 110, 25, 1.5
        gen_loss = (
            lambda_l1 * l1_loss_value +
            lambda_perceptual * perceptual_loss_value +
            lambda_bce * bce_loss_value_gen
        )

        # Discriminatorの損失
        bce_loss_value_real = bce_loss(tf.ones_like(real_output), real_output, smoothing=0.1)
        bce_loss_value_fake = bce_loss(tf.zeros_like(fake_output), fake_output, smoothing=0.1)
        disc_loss = bce_loss_value_real + bce_loss_value_fake

    # 勾配の適用
    gradients_of_generator = gen_tape.gradient(gen_loss, generator.trainable_variables)
    gradients_of_discriminator = disc_tape.gradient(disc_loss, discriminator.trainable_variables)

    generator_optimizer.apply_gradients(zip(gradients_of_generator, generator.trainable_variables))
    discriminator_optimizer.apply_gradients(zip(gradients_of_discriminator, discriminator.trainable_variables))

    return gen_loss, disc_loss, l1_loss_value, perceptual_loss_value, bce_loss_value_gen

# 画像フォルダのパス
overlay_folder = r"C:\Users\grape\Downloads\katachi\dataset5\datasets\kiiro\i-kiiro"
original_folder = r"C:\Users\grape\Downloads\katachi\dataset5\datasets\ori\i-ori"

# モデルの初期化
generator = build_generator_unet_with_residual()
discriminator = build_discriminator()

# データの分割
filenames = os.listdir(overlay_folder)
train_filenames, val_filenames = train_test_split(filenames, test_size=0.2, random_state=42)

# EarlyStoppingの初期化
early_stopping = EarlyStopping(patience=50, delta=0.001)

# 訓練ループ
batch_size = 16
epochs = 1000

# 損失を記録するリスト
generator_losses = []
discriminator_losses = []

# 訓練ループ（更新済み）
for epoch in range(epochs):
    epoch_gen_loss = 0
    epoch_disc_loss = 0
    num_batches = 0

    # 訓練データをバッチで取得
    for real_x_batch, real_y_batch in zip(load_images_from_filenames(train_filenames, overlay_folder, batch_size),
                                           load_images_from_filenames(train_filenames, original_folder, batch_size)):
        gen_loss, disc_loss, l1_loss_val, perc_loss_val, bce_loss_val_gen = train_step(real_x_batch, real_y_batch)
        epoch_gen_loss += gen_loss.numpy()
        epoch_disc_loss += disc_loss.numpy()
        num_batches += 1

    # エポックごとの損失を記録
    generator_losses.append(epoch_gen_loss / num_batches)
    discriminator_losses.append(epoch_disc_loss / num_batches)

    # 検証データでの評価
    val_x_batch = next(load_images_from_filenames(val_filenames, overlay_folder, batch_size))
    val_y_batch = next(load_images_from_filenames(val_filenames, original_folder, batch_size))
    val_fake_y = generator(val_x_batch, training=False)
    val_gen_loss, _, _, _, _ = train_step(val_x_batch, val_y_batch)

    # エポックごとの進捗表示
    if (epoch + 1) % 5 == 0:
        print(f"Epoch {epoch+1}/{epochs}")
        print(f"  Generator Loss: {epoch_gen_loss / num_batches:.4f}")
        print(f"  Discriminator Loss: {epoch_disc_loss / num_batches:.4f}")
        print(f"    Validation Loss: {val_gen_loss.numpy():.4f}")
        print(f"    L1 Loss: {l1_loss_val.numpy():.4f}")
        print(f"    Perceptual Loss: {perc_loss_val.numpy():.4f}")
        print(f"    BCE Loss (Gen): {bce_loss_val_gen.numpy():.4f}")

# 結果の可視化 (100エポックごと)
    if (epoch + 1) % 100 == 0:
        print(f"Visualizing results for Epoch {epoch + 1}")
        fake_y = generator(real_x_batch, training=False)
        plt.figure(figsize=(12, 6))
        plt.subplot(1, 2, 1)
        plt.imshow((real_x_batch[0] + 1) / 2)
        plt.title(f"Input (Epoch {epoch + 1})")
        plt.axis('off')

        plt.subplot(1, 2, 2)
        plt.imshow((fake_y[0] + 1) / 2)
        plt.title(f"Generated (Epoch {epoch + 1})")
        plt.axis('off')

        plt.show()

# モデルの保存 (100エポックごと)
    if (epoch + 1) % 300 == 0:
        generator.save(f"generator_epoch_{epoch + 1}.h5")
        discriminator.save(f"discriminator_epoch_{epoch + 1}.h5")
        print(f"Models saved at epoch {epoch + 1}")


    # 早期終了チェック
    if early_stopping.check(val_gen_loss.numpy()):
        print(f"Early stopping at epoch {epoch+1}")
        break

# 損失グラフをプロット
plt.figure(figsize=(10, 5))
plt.plot(range(1, len(generator_losses) + 1), generator_losses, label="Generator Loss")
plt.plot(range(1, len(discriminator_losses) + 1), discriminator_losses, label="Discriminator Loss")
plt.xlabel("Epoch")
plt.ylabel("Loss")
plt.title("Training Losses Over Epochs")
plt.legend()
plt.show()
























# In[28]:


# モデルの保存
generator.save('Generator_modeleurozen5.h5')   # Generatorモデルの保存
discriminator.save('Discriminator_model.h5')   # Discriminatorモデルの保存





# In[41]:


import os
import cv2
import numpy as np

# テストデータのディレクトリパス
test_image_dir =r"C:\Users\grape\Downloads\datasets\test"

# テストデータの画像ファイルリストを取得（拡張子が .png や .jpg のファイル）
test_images = [f for f in os.listdir(test_image_dir) if f.endswith('.png') or f.endswith('.jpg')]

# 画像の読み込みと前処理
def load_test_images(test_images, test_image_dir, img_size=(256, 256)):
    test_images_array = []  # テスト画像

    for test_image in test_images:
        test_image_path = os.path.join(test_image_dir, test_image)
        img = cv2.imread(test_image_path)
        img = cv2.resize(img, img_size)  # サイズを統一
        test_images_array.append(img)

    # NumPy配列に変換し、[-1, 1]に正規化
    test_images_array = np.array(test_images_array) / 127.5 - 1.0
    return test_images_array

# テストデータの読み込み
test_images_array = load_test_images(test_images, test_image_dir)
print(f"Loaded {test_images_array.shape[0]} test images.")


# In[ ]:





# In[4]:


# テストデータのフォルダパス
test_overlay_folder = r"C:\Users\grape\Downloads\datasets\test"
test_original_folder = r"C:\Users\grape\Downloads\datasets\j"

# テストデータのファイル名を取得
test_filenames = os.listdir(test_overlay_folder)

# テストデータをバッチでロードするジェネレーター
test_batch_size = 1
test_data_gen = load_images_from_filenames(test_filenames, test_overlay_folder, batch_size=test_batch_size)

# テストデータをバッチでロードするジェネレーター
for real_x_batch, real_y_batch in zip(test_data_gen, load_images_from_filenames(test_filenames, test_original_folder, batch_size=test_batch_size)):
    # 生成器の出力を得る（推論モード）
    fake_y = generator(real_x_batch, training=False)  # training=False で推論モード
    
    # 生成された画像を可視化
    plt.figure(figsize=(12, 6))
    plt.subplot(1, 2, 1)
    plt.imshow((real_x_batch[0] + 1) / 2)  # [-1, 1] -> [0, 1] に戻す
    plt.title("Input Image")
    plt.axis('off')

    plt.subplot(1, 2, 2)
    plt.imshow((fake_y[0] + 1) / 2)  # [-1, 1] -> [0, 1] に戻す
    plt.title("Generated Image")
    plt.axis('off')

    plt.show()

    # リサイズ: fake_yを生成画像に合わせる
    fake_y_resized = tf.image.resize(fake_y, size=(256, 256))
    real_y_batch_resized = tf.image.resize(real_y_batch, size=(256, 256))

    # L1 Loss を計算
    l1_loss_val = tf.reduce_mean(tf.abs(real_y_batch_resized - fake_y_resized))
    
    # perceptual lossを計算
    perceptual_loss_val = perceptual_loss(real_y_batch_resized, fake_y_resized)

    print(f"L1 Loss: {l1_loss_val.numpy():.4f}")
    print(f"Perceptual Loss: {perceptual_loss_val.numpy():.4f}")


# In[ ]:





# In[ ]:





# In[14]:


import cv2
import numpy as np
import tensorflow as tf
import os
import matplotlib.pyplot as plt

# マスク画像を読み込む関数
def load_masked_images(masked_image_dir, filenames, img_size=(256, 256)):
    masked_images = []

    for filename in filenames:
        # マスク画像を読み込み、サイズを統一
        masked_image_path = os.path.join(masked_image_dir, filename)
        masked_image = cv2.imread(masked_image_path)
        
        # BGRからRGBに変換
        masked_image = cv2.cvtColor(masked_image, cv2.COLOR_BGR2RGB)
        
        # 画像をリサイズ
        masked_image = cv2.resize(masked_image, img_size)
        
        # [-1, 1]に正規化
        masked_image = masked_image / 127.5 - 1.0
        masked_images.append(masked_image)

    return np.array(masked_images)

# テストデータのディレクトリパス
masked_image_dir = r"C:\Users\grape\Downloads\k\content\runs\segment\ki"

# ファイル名リストの取得
test_filenames = os.listdir(masked_image_dir)

# マスク画像をロード
masked_images_array = load_masked_images(masked_image_dir, test_filenames)

# 保存したGeneratorモデルを読み込む
generator = tf.keras.models.load_model('generator_epoch_300.h5') #Generator_modeleurozen5 generator_epoch_300

# 画像を1枚ずつ処理
for i in range(len(masked_images_array)):
    masked_image = masked_images_array[i]  # マスク画像

    # 生成器の出力を得る（推論モード）
    generated_image = generator.predict(np.expand_dims(masked_image, axis=0))  # バッチ次元を追加
    
    # [-1, 1]から[0, 255]に戻す
    generated_image = (generated_image + 1.0) * 127.5

    # 生成された画像を可視化
    plt.figure(figsize=(12, 6))
    
    # 入力画像（隠された画像）
    plt.subplot(1, 2, 1)
    plt.imshow((masked_image + 1) / 2)  # [-1, 1] -> [0, 1] に戻す
    plt.title("Masked Input Image")
    plt.axis('off')

    # 生成画像（隠された部分が補完された画像）
    plt.subplot(1, 2, 2)
    plt.imshow(generated_image[0] / 255.0)  # [0, 255] -> [0, 1] に戻す
    plt.title("Generated Image")
    plt.axis('off')

    plt.show()



# In[11]:


from IPython.display import FileLink

# ファイルへのリンクを表示
file_path = "Generator_modeleurozen.h5"
display(FileLink(file_path))


# In[ ]:






# In[ ]:





# In[ ]:




