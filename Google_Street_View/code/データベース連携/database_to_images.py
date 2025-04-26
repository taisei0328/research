import requests
from bs4 import BeautifulSoup
import random

# Google APIキーの設定
streetview_api_key = 'AIzaSyB-IZE4qhNO3ce-enFIky64yTNkS-8iJB0'

# 地名を取得するURL
base_url = 'https://geoshape.ex.nii.ac.jp/nrct/resource/'

def fetch_place_names(prefecture_name):
    response = requests.get(base_url)
    response.encoding = response.apparent_encoding
    if response.status_code != 200:
        print(f"Failed to retrieve data from {base_url}")
        return []

    soup = BeautifulSoup(response.text, 'html.parser')
    
    # 都道府県のリンクを見つける
    prefecture_link = None
    for link in soup.select('table#list a'):
        if prefecture_name in link.text:
            prefecture_link = link['href']
            break

    if not prefecture_link:
        print(f"Prefecture '{prefecture_name}' not found in the list.")
        return []

    # 見つけた県のページから地名を抽出
    prefecture_url = base_url + prefecture_link
    prefecture_response = requests.get(prefecture_url)
    prefecture_response.encoding = prefecture_response.apparent_encoding
    if prefecture_response.status_code != 200:
        print(f"Failed to retrieve data from {prefecture_url}")
        return []

    prefecture_soup = BeautifulSoup(prefecture_response.text, 'html.parser')
    
    places = []
    tbody = prefecture_soup.select_one('tbody')
    if tbody:
        for row in tbody.find_all('tr'):
            cols = row.find_all('td')
            if cols:
                # 地名と住所情報を取得
                display_info = f"{cols[4].get_text(strip=True)} {cols[2].get_text(strip=True)}"
                geocode_address = f"{cols[5].get_text(strip=True)} {cols[6].get_text(strip=True)}"
    
                latitude = cols[5].get_text(strip=True)
                longitude = cols[6].get_text(strip=True)
                
                if latitude and longitude:
                    places.append((display_info, latitude, longitude))
                
    return places

def fetch_streetview_image(lat, lng, heading, place):
    # display_info のスペースをアンダースコアに変換
    safe_place_name = place.replace(" ", "_")  # スペースをアンダースコアに変換
    streetview_url = f'https://maps.googleapis.com/maps/api/streetview?size=600x400&location={lat},{lng}&fov=120&heading={heading}&key={streetview_api_key}'
    response = requests.get(streetview_url)
    if response.status_code == 200:
        # ファイル名にスペースを含めないように
        filename = f'streetview_image_{safe_place_name}_{heading}.jpg'
        with open(filename, 'wb') as f:
            f.write(response.content)
        print(f"Image saved: {filename}")
    else:
        print(f"Failed to retrieve street view image for {place} at heading {heading}. Status: {response.status_code}")

def main():
    prefecture_name = input("県名を入力してください（例：佐賀県）: ")
    municipalities = fetch_place_names(prefecture_name)
    
    if not municipalities:
        print("No municipalities found.")
        return

    selected_places = random.sample(municipalities, min(4, len(municipalities)))
    for place_info in selected_places:
        display_info, lat, lng = place_info
        print(f"選ばれた地名: {display_info}")
        for heading in [0, 90, 180, 270]:
            fetch_streetview_image(lat, lng, heading, display_info)

if __name__ == "__main__":
    main()
