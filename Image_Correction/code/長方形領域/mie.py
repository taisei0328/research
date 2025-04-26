import requests
import random
import os
# Google Geocoding APIのAPIキー
geocoding_api_key = 'AIzaSyCIJwXOiKA8lmo1QrJrIEAAtawHvE65p64'

# Google Street View Static APIのAPIキー
streetview_api_key = 'AIzaSyBCuXxGSRE7uI-I36ob9mRH2AnozdtHwJ4'

# 東京都の境界座標
saga_boundary = {
    'min_lat':35.35,
    'max_lat': 35.45,
    'min_lng': 134.14,
    'max_lng': 134.24
}
#100枚の画像取得
for i in range(1):
# ランダムな座標を生成
    lat = random.uniform(saga_boundary['min_lat'], saga_boundary['max_lat'])
    lng = random.uniform(saga_boundary['min_lng'], saga_boundary['max_lng'])
    heading = 0
# 20枚の画像を取得する
    for j in range(4):
        fov = 120 
        heading = heading +90


    # Street View Static APIのURLを構築
        streetview_url = f'https://maps.googleapis.com/maps/api/streetview?size=600x400&location={lat},{lng}&fov={fov}&heading={heading}&key={streetview_api_key}'
    
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
                print(f"Image {j+1}: Address - {address}")

                

               # 画像をフォルダに保存
                with open(os.path.join(f'streetview_image_{i+1}_{j+1}.jpg'), 'wb') as f:
                    f.write(streetview_response.content)
            else:
                print(f"No address found for coordinates: {lat}, {lng}")
        else:
            print(f"Failed to fetch address for coordinates: {lat}, {lng}")