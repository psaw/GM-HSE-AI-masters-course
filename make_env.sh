sudo apt install python3-pip -y
sudo apt install python3.10-venv -y
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
# pip install ipykernel ipython jupyter_client jupyter_core matplotlib torch torchvision tqdm