import requests
import random
import os

# Google Geocoding APIのAPIキー
geocoding_api_key = 'AIzaSyDfTGjzPvpBe4uSOLy8cJ8SCtOrkz4J1i0'

# Google Street View Static APIのAPIキー
streetview_api_key = 'AIzaSyDfTGjzPvpBe4uSOLy8cJ8SCtOrkz4J1i0'

# 佐賀県の境界座標
saga_boundary = {
    'min_lat': 33.26,
    'max_lat': 33.27,
    'min_lng': 129.86,
    'max_lng': 129.87
}

# 前進する量（緯度・経度を少しずつ動かす）
lat_increment = 0.0001
lng_increment = 0.0001

# 画像を取得する回数
for i in range(200):
    # ランダムな座標を生成
    lat = random.uniform(saga_boundary['min_lat'], saga_boundary['max_lat'])
    lng = random.uniform(saga_boundary['min_lng'], saga_boundary['max_lng'])

    # 1つの場所につき4回座標を進めて画像を取得
    for j in range(2):
        # 各方向（0°, 90°, 180°, 270°）で画像を取得
        for heading in [90,270]:
            # Street View Static APIのURLを構築
            streetview_url = f'https://maps.googleapis.com/maps/api/streetview?size=600x400&location={lat},{lng}&fov=120&heading={heading}&key={streetview_api_key}'

            # Geocoding APIのURLを構築
            geocoding_url = f'https://maps.googleapis.com/maps/api/geocode/json?latlng={lat},{lng}&key={geocoding_api_key}'

            # APIにリクエストを送信して画像を取得
            streetview_response = requests.get(streetview_url)
            geocoding_response = requests.get(geocoding_url)

            # 住所情報を取得
            if geocoding_response.status_code == 200:
                geocoding_data = geocoding_response.json()
                if geocoding_data['status'] == 'OK':
                    address = geocoding_data['results'][0]['formatted_address']
                    print(f"Image {j+1}, Heading {heading}°: Address - {address}")

                    # 画像をフォルダに保存
                    image_filename = f'streetview_image_{i+1}_{j+1}_{heading}.jpg'
                    with open(os.path.join(image_filename), 'wb') as f:
                        f.write(streetview_response.content)

            else:
                print(f"Failed to fetch address for coordinates: {lat}, {lng}")

        # 座標を前進させる
        lat += lat_increment
        lng += lng_increment
