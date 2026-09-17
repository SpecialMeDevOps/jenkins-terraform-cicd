# Hulka nginx image - poori website serve karne ke liye
FROM nginx:alpine

# Purani default files hata do
RUN rm -rf /usr/share/nginx/html/*

# Apni website ki files nginx ke andar copy karo
COPY index.html /usr/share/nginx/html/
COPY style.css  /usr/share/nginx/html/
COPY script.js  /usr/share/nginx/html/

# Port 80 expose karo
EXPOSE 80

# Nginx foreground mein chalega
CMD ["nginx", "-g", "daemon off;"]
